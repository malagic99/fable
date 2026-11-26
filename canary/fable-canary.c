/*
 * fable-canary — a tiny Windows program Fable runs in a throwaway prefix to
 * find out what an engine can actually do, one rung at a time:
 *
 *   pe      this program started (Wine can run a Windows executable)
 *   dll.*   the Direct3D DLLs load
 *   d3d12.* a D3D12 device and a command queue can be created, before
 *           anything else has touched the renderer
 *   adapter a graphics adapter is reported
 *   d3d11.* a D3D11 device can be created
 *   winemetal  DXMT's Metal bridge is in the process, so the D3D11 device
 *           came from DXMT and not from Wine's own d3d11
 *   present a small window gets a D3D11 swap chain and one frame is
 *           presented in it: a renderer that makes devices but can't reach
 *           a window (DXMT on Wine 11.10) runs no game
 *
 * With "no-d3d12" as argv[2] the D3D12 rungs are reported skipped without
 * loading d3d12.dll: DXMT has no D3D12, and Wine's own would only test
 * something a DXMT game never uses.
 *
 * It writes one "key=value" line per fact to the file named by argv[1] (or
 * stdout), flushing after each, so a crash part-way still leaves everything
 * learned up to that point. Its only drawing is one cleared frame in a small
 * window, and it never claims a game works: a device and a presented frame
 * prove the renderer is wired up, nothing more.
 *
 * Every Direct3D entry point is looked up at run time rather than imported,
 * so a missing DLL is reported as a failed rung instead of stopping the
 * program before it can say anything.
 *
 * Build: scripts/build-canary.sh (mingw-w64). GPL-3.0-only, like Fable.
 */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <dxgi.h>
#include <d3d11.h>
#include <d3d12.h>

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

static HMODULE load(const char *name, const char *key)
{
    char path[MAX_PATH] = "";
    HMODULE module;

    stage = key;
    module = LoadLibraryA(name);
    if (!module) {
        say("%s=failed error=%lu", key, (unsigned long)GetLastError());
        return NULL;
    }
    GetModuleFileNameA(module, path, sizeof(path));
    say("%s=ok path=%s", key, path);
    return module;
}

typedef HRESULT (WINAPI *create_factory_fn)(REFIID, void **);
typedef HRESULT (WINAPI *create_device12_fn)(IUnknown *, D3D_FEATURE_LEVEL, REFIID, void **);
typedef HRESULT (WINAPI *create_device_swapchain11_fn)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
                                                       const D3D_FEATURE_LEVEL *, UINT, UINT,
                                                       const DXGI_SWAP_CHAIN_DESC *, IDXGISwapChain **,
                                                       ID3D11Device **, D3D_FEATURE_LEVEL *,
                                                       ID3D11DeviceContext **);
typedef HRESULT (WINAPI *create_device11_fn)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
                                             const D3D_FEATURE_LEVEL *, UINT, UINT,
                                             ID3D11Device **, D3D_FEATURE_LEVEL *,
                                             ID3D11DeviceContext **);

/*
 * A small window, a swap chain on it and one presented frame: the path every
 * game takes to the screen. Device creation alone doesn't touch it.
 */
static void present_rung(HMODULE d3d11)
{
    create_device_swapchain11_fn create = (create_device_swapchain11_fn)(void *)GetProcAddress(d3d11, "D3D11CreateDeviceAndSwapChain");
    DXGI_SWAP_CHAIN_DESC desc;
    IDXGISwapChain *swapchain = NULL;
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    HWND window;
    HRESULT hr;

    stage = "present";
    window = CreateWindowExA(WS_EX_TOOLWINDOW, "STATIC", "Fable engine test", WS_POPUP | WS_VISIBLE,
                             0, 0, 128, 128, NULL, NULL, GetModuleHandleA(NULL), NULL);
    if (!window) {
        say("present=failed error=%lu", (unsigned long)GetLastError());
        return;
    }
    memset(&desc, 0, sizeof(desc));
    desc.BufferDesc.Width = 128;
    desc.BufferDesc.Height = 128;
    desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 2;
    desc.OutputWindow = window;
    desc.Windowed = TRUE;
    desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    hr = create
        ? create(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION,
                 &desc, &swapchain, &device, NULL, &context)
        : E_NOINTERFACE;
    if (SUCCEEDED(hr) && swapchain) hr = IDXGISwapChain_Present(swapchain, 0, 0);
    if (SUCCEEDED(hr) && swapchain) say("present=ok");
    else say("present=failed hr=0x%08lx", (unsigned long)hr);
    if (swapchain) IDXGISwapChain_Release(swapchain);
    if (context) ID3D11DeviceContext_Release(context);
    if (device) ID3D11Device_Release(device);
    DestroyWindow(window);
}

int main(int argc, char **argv)
{
    HMODULE dxgi, d3d12 = NULL, d3d11;
    int no_d3d12 = argc > 2 && !strcmp(argv[2], "no-d3d12");
    IDXGIAdapter1 *adapter = NULL;

    out = stdout;
    if (argc > 1) {
        FILE *file = fopen(argv[1], "w");
        if (file) out = file;
    }
    SetUnhandledExceptionFilter(on_crash);
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);

    say("fable-canary 1");
    say("pe=ok bits=%d", (int)(sizeof(void *) * 8));
    if (argc > 2 && !strcmp(argv[2], "pe-only")) {
        say("done");
        return 0;
    }

    if (no_d3d12) say("dll.d3d12=skipped");
    else d3d12 = load("d3d12.dll", "dll.d3d12");

    /*
     * D3D12 first, and cold: no DXGI factory has been created yet, so nothing
     * has pulled the renderer into the process on d3d12's behalf. Unreal
     * Engine probes D3D12 this way. Creating the factory first hides a
     * d3d12 that cannot find its renderer on its own (the v1.2.0 rpath bug).
     */
    if (d3d12) {
        create_device12_fn create_device = (create_device12_fn)(void *)GetProcAddress(d3d12, "D3D12CreateDevice");
        ID3D12Device *device = NULL;
        HRESULT hr;

        stage = "d3d12.device";
        hr = create_device
            ? create_device(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device)
            : E_NOINTERFACE;
        if (SUCCEEDED(hr) && device) {
            D3D12_COMMAND_QUEUE_DESC desc;
            ID3D12CommandQueue *queue = NULL;

            say("d3d12.device=ok");
            stage = "d3d12.queue";
            memset(&desc, 0, sizeof(desc));
            desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
            hr = ID3D12Device_CreateCommandQueue(device, &desc, &IID_ID3D12CommandQueue, (void **)&queue);
            if (SUCCEEDED(hr) && queue) {
                say("d3d12.queue=ok");
                ID3D12CommandQueue_Release(queue);
            } else {
                say("d3d12.queue=failed hr=0x%08lx", (unsigned long)hr);
            }
            ID3D12Device_Release(device);
        } else {
            say("d3d12.device=failed hr=0x%08lx", (unsigned long)hr);
            say("d3d12.queue=skipped");
        }
    } else {
        say("d3d12.device=skipped");
        say("d3d12.queue=skipped");
    }

    dxgi = load("dxgi.dll", "dll.dxgi");
    if (dxgi) {
        create_factory_fn create_factory = (create_factory_fn)(void *)GetProcAddress(dxgi, "CreateDXGIFactory1");
        IDXGIFactory1 *factory = NULL;
        HRESULT hr;

        stage = "adapter";
        hr = create_factory ? create_factory(&IID_IDXGIFactory1, (void **)&factory) : E_NOINTERFACE;
        if (SUCCEEDED(hr) && factory) hr = IDXGIFactory1_EnumAdapters1(factory, 0, &adapter);
        if (SUCCEEDED(hr) && adapter) {
            DXGI_ADAPTER_DESC1 desc;
            char name[256] = "";

            memset(&desc, 0, sizeof(desc));
            IDXGIAdapter1_GetDesc1(adapter, &desc);
            WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, name, sizeof(name) - 1, NULL, NULL);
            say("adapter=ok vendor=0x%04x device=0x%04x vram_mb=%lu name=%s",
                desc.VendorId, desc.DeviceId,
                (unsigned long)(desc.DedicatedVideoMemory >> 20), name);
        } else {
            say("adapter=failed hr=0x%08lx", (unsigned long)hr);
        }
    } else {
        say("adapter=skipped");
    }

    d3d11 = load("d3d11.dll", "dll.d3d11");
    if (d3d11) {
        create_device11_fn create_device = (create_device11_fn)(void *)GetProcAddress(d3d11, "D3D11CreateDevice");
        ID3D11Device *device = NULL;
        ID3D11DeviceContext *context = NULL;
        D3D_FEATURE_LEVEL level = 0;
        HRESULT hr;

        stage = "d3d11.device";
        hr = create_device
            ? create_device(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION,
                            &device, &level, &context)
            : E_NOINTERFACE;
        if (SUCCEEDED(hr) && device) {
            say("d3d11.device=ok level=0x%04x", (unsigned)level);
            say("winemetal=%s", GetModuleHandleA("winemetal.dll") ? "ok" : "failed not loaded");
            if (context) ID3D11DeviceContext_Release(context);
            ID3D11Device_Release(device);
            present_rung(d3d11);
        } else {
            say("d3d11.device=failed hr=0x%08lx", (unsigned long)hr);
            say("winemetal=skipped");
            say("present=skipped");
        }
    } else {
        say("d3d11.device=skipped");
        say("winemetal=skipped");
        say("present=skipped");
    }

    if (adapter) IDXGIAdapter1_Release(adapter);
    stage = "done";
    say("done");
    return 0;
}
