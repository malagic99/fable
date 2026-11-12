/*
 * fable-bench — a fixed Direct3D 12 scene Fable times on an engine, in a
 * throwaway prefix. It answers one question: how fast does *this engine*
 * turn the same D3D12 work into frames on *this Mac*? Run on two engines, it
 * says whether one is slower than the other before a bottle is moved.
 *
 * It is synthetic. It never says how any game will run.
 *
 * Two phases, each timed for a fixed wall time after a warm-up:
 *
 *   draws   20000 small triangles, one draw call each, with a constant
 *           changed between them. Bound by the CPU side: Wine plus the
 *           renderer translating D3D12 calls. This is where engines differ.
 *   shade   one full-screen triangle (2560x1440) with a 256-step loop per pixel.
 *           Bound by the GPU. Mostly the same on any engine — a sanity
 *           check that the renderer isn't doing something far off.
 *
 * A frame's time is measured from the start of recording it to the GPU
 * reporting it finished (a fence). The timed frames are drawn to an
 * off-screen texture: drawn to the window, every frame waits for the display
 * and the result is just its refresh rate (8.3 ms on a 120 Hz screen, which
 * is what the first version of this measured). Separately, frames are
 * presented to a real window — that is the ladder's "a frame is presented"
 * rung, and it is not timed.
 *
 * Output: one flushed "key=value" line per fact, to argv[1] or stdout.
 * Build: scripts/build-canary.sh (mingw-w64). GPL-3.0-only, like Fable.
 */
#define COBJMACROS
#define WIDL_C_INLINE_WRAPPERS
#define INITGUID
#include <windows.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dxgi1_4.h>
#include <d3d12.h>
#include <d3dcommon.h>

#define WIDTH 1280
#define HEIGHT 720
#define BUFFERS 2
/* The timed frames are drawn at this size, larger than the window, so the
 * shading phase takes long enough to measure on a fast GPU. */
#define OFF_WIDTH 2560
#define OFF_HEIGHT 1440
#define DRAWS 20000
#define SHADE_STEPS 256
#define WARMUP_FRAMES 30
#define PHASE_SECONDS 3.0
#define MAX_FRAMES 20000

static FILE *out;
static const char *stage = "start";

static void say(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    vfprintf(out, format, args);
    va_end(args);
    fputc('\n', out);
    fflush(out);
}

static LONG WINAPI on_crash(EXCEPTION_POINTERS *info)
{
    say("crash=0x%08lx stage=%s", (unsigned long)info->ExceptionRecord->ExceptionCode, stage);
    ExitProcess(3);
    return EXCEPTION_EXECUTE_HANDLER;
}

/* Reports a failed step and ends the run. Later steps are never written. */
static void fail(const char *key, HRESULT hr)
{
    say("%s=failed hr=0x%08lx", key, (unsigned long)hr);
    say("done");
    ExitProcess(2);
}

/* Loads a library, or reports which one would not load and ends the run. */
static HMODULE load(const char *name)
{
    HMODULE module = LoadLibraryA(name);
    if (!module) {
        say("libraries=failed error=%lu dll=%s", (unsigned long)GetLastError(), name);
        say("done");
        ExitProcess(2);
    }
    return module;
}

static const char shader_source[] =
    "cbuffer C : register(b0) { float4 p; }\n"
    "struct V { float4 pos : SV_Position; float2 uv : TEXCOORD0; };\n"
    "V vs(uint id : SV_VertexID) {\n"
    "    V o;\n"
    "    if (p.z < 0.5) {\n"
    "        float2 t = float2((id << 1) & 2, id & 2);\n"
    "        o.pos = float4(t * 2.0 - 1.0, 0.0, 1.0);\n"
    "        o.uv = t;\n"
    "    } else {\n"
    "        float a = p.y * 0.61803;\n"
    "        float2 c = float2(frac(a) * 2.0 - 1.0, frac(a * 7.13) * 2.0 - 1.0);\n"
    "        float2 d = float2(0.0, 0.03);\n"
    "        if (id == 1) d = float2(0.02, -0.02);\n"
    "        if (id == 2) d = float2(-0.02, -0.02);\n"
    "        o.pos = float4(c + d, 0.0, 1.0);\n"
    "        o.uv = c;\n"
    "    }\n"
    "    return o;\n"
    "}\n"
    "float4 ps(V i) : SV_Target {\n"
    "    if (p.z > 0.5) return float4(frac(i.uv * 3.0), 0.5, 1.0);\n"
    "    float2 z = float2(0.0, 0.0);\n"
    "    float2 c = (i.uv - 0.5) * 3.0 + float2(sin(p.x) * 0.1, 0.0);\n"
    "    float n = 0.0;\n"
    "    for (int k = 0; k < 256; k++) {\n"
    "        z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;\n"
    "        if (dot(z, z) < 4.0) n += 1.0;\n"
    "    }\n"
    "    return float4(n / 256.0, frac(n * 0.07), 0.3, 1.0);\n"
    "}\n";

typedef HRESULT (WINAPI *compile_fn)(const void *, SIZE_T, const char *, const void *, void *,
                                     const char *, const char *, UINT, UINT, ID3DBlob **, ID3DBlob **);
typedef HRESULT (WINAPI *create_factory_fn)(REFIID, void **);
typedef HRESULT (WINAPI *create_device_fn)(IUnknown *, D3D_FEATURE_LEVEL, REFIID, void **);
typedef HRESULT (WINAPI *serialize_fn)(const D3D12_ROOT_SIGNATURE_DESC *, D3D_ROOT_SIGNATURE_VERSION,
                                       ID3DBlob **, ID3DBlob **);

static ID3D12Device *device;
static ID3D12CommandQueue *queue;
static ID3D12CommandAllocator *allocator;
static ID3D12GraphicsCommandList *list;
static IDXGISwapChain3 *swapchain;
static ID3D12Resource *targets[BUFFERS];
static ID3D12Resource *offscreen;
static ID3D12DescriptorHeap *heap;
static UINT rtv_size;
static ID3D12RootSignature *root;
static ID3D12PipelineState *pipeline;
static ID3D12Fence *fence;
static HANDLE fence_event;
static UINT64 fence_value;
static LARGE_INTEGER frequency;

static double now_ms(void)
{
    LARGE_INTEGER counter;
    QueryPerformanceCounter(&counter);
    return (double)counter.QuadPart * 1000.0 / (double)frequency.QuadPart;
}

static LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    return DefWindowProcA(window, message, wparam, lparam);
}

static void pump(void)
{
    MSG message;
    while (PeekMessageA(&message, NULL, 0, 0, PM_REMOVE)) {
        TranslateMessage(&message);
        DispatchMessageA(&message);
    }
}

static void transition(ID3D12Resource *resource, D3D12_RESOURCE_STATES before, D3D12_RESOURCE_STATES after)
{
    D3D12_RESOURCE_BARRIER barrier;
    memset(&barrier, 0, sizeof(barrier));
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = resource;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    barrier.Transition.StateBefore = before;
    barrier.Transition.StateAfter = after;
    ID3D12GraphicsCommandList_ResourceBarrier(list, 1, &barrier);
}

/*
 * Records and submits one frame — to the window's back buffer and then
 * presented when `present` is set, otherwise to the off-screen texture.
 * Returns the milliseconds from the start of recording to the GPU finishing
 * it, or a negative number if the GPU never reported back (-1) or the
 * present failed (-2).
 */
static double frame(int mode, float time, int present)
{
    static const float clear[4] = { 0.02f, 0.02f, 0.05f, 1.0f };
    D3D12_CPU_DESCRIPTOR_HANDLE rtv;
    D3D12_VIEWPORT viewport = { 0.0f, 0.0f, (float)(present ? WIDTH : OFF_WIDTH),
                                (float)(present ? HEIGHT : OFF_HEIGHT), 0.0f, 1.0f };
    D3D12_RECT scissor = { 0, 0, present ? WIDTH : OFF_WIDTH, present ? HEIGHT : OFF_HEIGHT };
    ID3D12CommandList *lists[1];
    float constants[4] = { time, 0.0f, (float)mode, 0.0f };
    UINT index = present ? IDXGISwapChain3_GetCurrentBackBufferIndex(swapchain) : BUFFERS;
    double start = now_ms(), finished;
    int i;

    ID3D12CommandAllocator_Reset(allocator);
    ID3D12GraphicsCommandList_Reset(list, allocator, pipeline);
    if (present) transition(targets[index], D3D12_RESOURCE_STATE_PRESENT, D3D12_RESOURCE_STATE_RENDER_TARGET);
    rtv = ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(heap);
    rtv.ptr += (SIZE_T)index * rtv_size;
    ID3D12GraphicsCommandList_OMSetRenderTargets(list, 1, &rtv, FALSE, NULL);
    ID3D12GraphicsCommandList_ClearRenderTargetView(list, rtv, clear, 0, NULL);
    ID3D12GraphicsCommandList_RSSetViewports(list, 1, &viewport);
    ID3D12GraphicsCommandList_RSSetScissorRects(list, 1, &scissor);
    ID3D12GraphicsCommandList_SetGraphicsRootSignature(list, root);
    ID3D12GraphicsCommandList_IASetPrimitiveTopology(list, D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    if (mode == 0) {
        ID3D12GraphicsCommandList_SetGraphicsRoot32BitConstants(list, 0, 4, constants, 0);
        ID3D12GraphicsCommandList_DrawInstanced(list, 3, 1, 0, 0);
    } else {
        for (i = 0; i < DRAWS; i++) {
            constants[1] = (float)i + time;
            ID3D12GraphicsCommandList_SetGraphicsRoot32BitConstants(list, 0, 4, constants, 0);
            ID3D12GraphicsCommandList_DrawInstanced(list, 3, 1, 0, 0);
        }
    }
    if (present) transition(targets[index], D3D12_RESOURCE_STATE_RENDER_TARGET, D3D12_RESOURCE_STATE_PRESENT);
    ID3D12GraphicsCommandList_Close(list);

    lists[0] = (ID3D12CommandList *)list;
    ID3D12CommandQueue_ExecuteCommandLists(queue, 1, lists);
    fence_value++;
    ID3D12CommandQueue_Signal(queue, fence, fence_value);
    if (ID3D12Fence_GetCompletedValue(fence) < fence_value) {
        ID3D12Fence_SetEventOnCompletion(fence, fence_value, fence_event);
        if (WaitForSingleObject(fence_event, 10000) != WAIT_OBJECT_0) return -1.0;
    }
    finished = now_ms();

    if (present && FAILED(IDXGISwapChain3_Present(swapchain, 0, 0))) return -2.0;
    pump();
    return finished - start;
}

static int compare_doubles(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

static void phase(const char *name, int mode)
{
    static double times[MAX_FRAMES];
    double begin, total = 0.0, elapsed;
    int count = 0, i;
    char key[32];

    snprintf(key, sizeof(key), "phase.%s", name);
    stage = name;
    for (i = 0; i < WARMUP_FRAMES; i++) {
        double t = frame(mode, (float)i * 0.01f, 0);
        if (t < 0.0) {
            say("%s=failed reason=%s", key, t < -1.5 ? "present" : "gpu-timeout");
            return;
        }
    }
    begin = now_ms();
    while (count < MAX_FRAMES && now_ms() - begin < PHASE_SECONDS * 1000.0) {
        double t = frame(mode, (float)count * 0.01f, 0);
        if (t < 0.0) {
            say("%s=failed reason=%s frames=%d", key, t < -1.5 ? "present" : "gpu-timeout", count);
            return;
        }
        times[count++] = t;
        total += t;
    }
    elapsed = now_ms() - begin;
    if (count < 10) {
        say("%s=failed reason=too-few-frames frames=%d", key, count);
        return;
    }
    qsort(times, (size_t)count, sizeof(double), compare_doubles);
    say("%s=ok frames=%d wall_ms=%.0f avg_ms=%.3f median_ms=%.3f p99_ms=%.3f",
        key, count, elapsed, total / count, times[count / 2], times[(count * 99) / 100]);
    /* Show what was just timed, so the window isn't blank while it runs. */
    frame(mode, 0.0f, 1);
}

int main(int argc, char **argv)
{
    HMODULE d3d12, dxgi, compiler;
    create_factory_fn create_factory;
    create_device_fn create_device;
    serialize_fn serialize;
    compile_fn compile;
    IDXGIFactory4 *factory = NULL;
    IDXGISwapChain1 *swapchain1 = NULL;
    ID3DBlob *vs = NULL, *ps = NULL, *signature = NULL, *errors = NULL;
    D3D12_COMMAND_QUEUE_DESC queue_desc;
    DXGI_SWAP_CHAIN_DESC1 swap_desc;
    D3D12_DESCRIPTOR_HEAP_DESC heap_desc;
    D3D12_ROOT_PARAMETER parameter;
    D3D12_ROOT_SIGNATURE_DESC root_desc;
    D3D12_GRAPHICS_PIPELINE_STATE_DESC pipeline_desc;
    D3D12_CPU_DESCRIPTOR_HANDLE rtv;
    WNDCLASSA window_class;
    RECT rect = { 0, 0, WIDTH, HEIGHT };
    HWND window;
    HRESULT hr;
    UINT i;

    out = stdout;
    if (argc > 1) {
        FILE *file = fopen(argv[1], "w");
        if (file) out = file;
    }
    SetUnhandledExceptionFilter(on_crash);
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
    QueryPerformanceFrequency(&frequency);

    say("fable-bench 1");
    say("scene=ok width=%d height=%d draws=%d steps=%d seconds=%.0f",
        OFF_WIDTH, OFF_HEIGHT, DRAWS, SHADE_STEPS, PHASE_SECONDS);

    stage = "libraries";
    d3d12 = load("d3d12.dll");
    dxgi = load("dxgi.dll");
    compiler = load("d3dcompiler_47.dll");
    create_device = (create_device_fn)(void *)GetProcAddress(d3d12, "D3D12CreateDevice");
    serialize = (serialize_fn)(void *)GetProcAddress(d3d12, "D3D12SerializeRootSignature");
    create_factory = (create_factory_fn)(void *)GetProcAddress(dxgi, "CreateDXGIFactory1");
    compile = (compile_fn)(void *)GetProcAddress(compiler, "D3DCompile");
    if (!create_device || !serialize || !create_factory || !compile) fail("libraries", E_NOINTERFACE);
    say("libraries=ok");

    stage = "device";
    hr = create_device(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device);
    if (FAILED(hr)) fail("device", hr);
    memset(&queue_desc, 0, sizeof(queue_desc));
    queue_desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    hr = ID3D12Device_CreateCommandQueue(device, &queue_desc, &IID_ID3D12CommandQueue, (void **)&queue);
    if (FAILED(hr)) fail("device", hr);
    say("device=ok");

    stage = "window";
    memset(&window_class, 0, sizeof(window_class));
    window_class.lpfnWndProc = window_proc;
    window_class.hInstance = GetModuleHandleA(NULL);
    window_class.lpszClassName = "FableBench";
    window_class.hCursor = LoadCursorA(NULL, (LPCSTR)IDC_ARROW);
    RegisterClassA(&window_class);
    AdjustWindowRect(&rect, WS_OVERLAPPED | WS_CAPTION, FALSE);
    window = CreateWindowExA(0, "FableBench", "Fable engine benchmark", WS_OVERLAPPED | WS_CAPTION,
                             60, 60, rect.right - rect.left, rect.bottom - rect.top,
                             NULL, NULL, window_class.hInstance, NULL);
    if (!window) fail("window", HRESULT_FROM_WIN32(GetLastError()));
    ShowWindow(window, SW_SHOWNOACTIVATE);
    pump();
    say("window=ok");

    stage = "swapchain";
    hr = create_factory(&IID_IDXGIFactory4, (void **)&factory);
    if (FAILED(hr)) fail("swapchain", hr);
    memset(&swap_desc, 0, sizeof(swap_desc));
    swap_desc.Width = WIDTH;
    swap_desc.Height = HEIGHT;
    swap_desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    swap_desc.SampleDesc.Count = 1;
    swap_desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swap_desc.BufferCount = BUFFERS;
    swap_desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    hr = IDXGIFactory4_CreateSwapChainForHwnd(factory, (IUnknown *)queue, window, &swap_desc, NULL, NULL, &swapchain1);
    if (FAILED(hr)) fail("swapchain", hr);
    hr = IDXGISwapChain1_QueryInterface(swapchain1, &IID_IDXGISwapChain3, (void **)&swapchain);
    if (FAILED(hr)) fail("swapchain", hr);
    memset(&heap_desc, 0, sizeof(heap_desc));
    heap_desc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    heap_desc.NumDescriptors = BUFFERS + 1;
    hr = ID3D12Device_CreateDescriptorHeap(device, &heap_desc, &IID_ID3D12DescriptorHeap, (void **)&heap);
    if (FAILED(hr)) fail("swapchain", hr);
    rtv_size = ID3D12Device_GetDescriptorHandleIncrementSize(device, D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    rtv = ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(heap);
    for (i = 0; i < BUFFERS; i++) {
        hr = IDXGISwapChain3_GetBuffer(swapchain, i, &IID_ID3D12Resource, (void **)&targets[i]);
        if (FAILED(hr)) fail("swapchain", hr);
        ID3D12Device_CreateRenderTargetView(device, targets[i], NULL, rtv);
        rtv.ptr += rtv_size;
    }
    {
        /* The texture the timed frames are drawn to; its view is the heap's
         * last slot. It stays a render target for the whole run. */
        D3D12_HEAP_PROPERTIES properties;
        D3D12_RESOURCE_DESC desc;
        D3D12_CLEAR_VALUE clear;

        memset(&properties, 0, sizeof(properties));
        properties.Type = D3D12_HEAP_TYPE_DEFAULT;
        memset(&desc, 0, sizeof(desc));
        desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
        desc.Width = OFF_WIDTH;
        desc.Height = OFF_HEIGHT;
        desc.DepthOrArraySize = 1;
        desc.MipLevels = 1;
        desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        desc.SampleDesc.Count = 1;
        desc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
        memset(&clear, 0, sizeof(clear));
        clear.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        clear.Color[0] = 0.02f; clear.Color[1] = 0.02f; clear.Color[2] = 0.05f; clear.Color[3] = 1.0f;
        hr = ID3D12Device_CreateCommittedResource(device, &properties, D3D12_HEAP_FLAG_NONE, &desc,
                                                  D3D12_RESOURCE_STATE_RENDER_TARGET, &clear,
                                                  &IID_ID3D12Resource, (void **)&offscreen);
        if (FAILED(hr)) fail("swapchain", hr);
        ID3D12Device_CreateRenderTargetView(device, offscreen, NULL, rtv);
    }
    say("swapchain=ok");

    stage = "shaders";
    hr = compile(shader_source, sizeof(shader_source) - 1, "fable-bench", NULL, NULL, "vs", "vs_5_0", 0, 0, &vs, &errors);
    if (FAILED(hr)) fail("shaders", hr);
    hr = compile(shader_source, sizeof(shader_source) - 1, "fable-bench", NULL, NULL, "ps", "ps_5_0", 0, 0, &ps, &errors);
    if (FAILED(hr)) fail("shaders", hr);
    say("shaders=ok");

    stage = "pipeline";
    memset(&parameter, 0, sizeof(parameter));
    parameter.ParameterType = D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS;
    parameter.Constants.ShaderRegister = 0;
    parameter.Constants.Num32BitValues = 4;
    parameter.ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;
    memset(&root_desc, 0, sizeof(root_desc));
    root_desc.NumParameters = 1;
    root_desc.pParameters = &parameter;
    hr = serialize(&root_desc, D3D_ROOT_SIGNATURE_VERSION_1, &signature, &errors);
    if (FAILED(hr)) fail("pipeline", hr);
    hr = ID3D12Device_CreateRootSignature(device, 0, ID3D10Blob_GetBufferPointer(signature),
                                          ID3D10Blob_GetBufferSize(signature), &IID_ID3D12RootSignature, (void **)&root);
    if (FAILED(hr)) fail("pipeline", hr);
    memset(&pipeline_desc, 0, sizeof(pipeline_desc));
    pipeline_desc.pRootSignature = root;
    pipeline_desc.VS.pShaderBytecode = ID3D10Blob_GetBufferPointer(vs);
    pipeline_desc.VS.BytecodeLength = ID3D10Blob_GetBufferSize(vs);
    pipeline_desc.PS.pShaderBytecode = ID3D10Blob_GetBufferPointer(ps);
    pipeline_desc.PS.BytecodeLength = ID3D10Blob_GetBufferSize(ps);
    pipeline_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;
    pipeline_desc.SampleMask = 0xffffffffu;
    pipeline_desc.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID;
    pipeline_desc.RasterizerState.CullMode = D3D12_CULL_MODE_NONE;
    pipeline_desc.RasterizerState.DepthClipEnable = TRUE;
    pipeline_desc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
    pipeline_desc.NumRenderTargets = 1;
    pipeline_desc.RTVFormats[0] = DXGI_FORMAT_R8G8B8A8_UNORM;
    pipeline_desc.SampleDesc.Count = 1;
    hr = ID3D12Device_CreateGraphicsPipelineState(device, &pipeline_desc, &IID_ID3D12PipelineState, (void **)&pipeline);
    if (FAILED(hr)) fail("pipeline", hr);
    hr = ID3D12Device_CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void **)&allocator);
    if (FAILED(hr)) fail("pipeline", hr);
    hr = ID3D12Device_CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator, pipeline,
                                        &IID_ID3D12GraphicsCommandList, (void **)&list);
    if (FAILED(hr)) fail("pipeline", hr);
    ID3D12GraphicsCommandList_Close(list);
    hr = ID3D12Device_CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence);
    if (FAILED(hr)) fail("pipeline", hr);
    fence_event = CreateEventA(NULL, FALSE, FALSE, NULL);
    say("pipeline=ok");

    stage = "present";
    {
        double first = frame(0, 0.0f, 1);
        if (first < 0.0) {
            say("present=failed reason=%s", first < -1.5 ? "present" : "gpu-timeout");
            say("done");
            return 2;
        }
        say("present=ok first_ms=%.3f", first);
    }

    phase("draws", 1);
    phase("shade", 0);

    stage = "done";
    DestroyWindow(window);
    say("done");
    return 0;
}
