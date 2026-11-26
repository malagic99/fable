/* d3d11-smoke: off-screen D3D11 checks for comparing DXMT builds.
 * One flushed "key=value" line per rung to argv[1] (or stdout).
 *   device    D3D11CreateDevice (hardware)
 *   compile   D3DCompile of a VS and PS (d3dcompiler_47)
 *   shaders   CreateVertexShader/CreatePixelShader (DXMT's airconv runs here or at draw)
 *   draw      a full-screen triangle into a 64x64 RGBA8 target, read back via a staging copy
 *   pixel     the centre pixel's RGBA
 *   staging_update  UpdateSubresource into a STAGING texture (upstream aborted; patch 0005)
 *   query     an occlusion query that ends right after a draw completes (upstream hung; patch 0004)
 */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <stdio.h>
#include <d3d11.h>
#include <d3dcompiler.h>

static FILE *out;
static void say(const char *k, const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    fprintf(out, "%s=", k); vfprintf(out, fmt, ap); fputc('\n', out); fflush(out);
    va_end(ap);
}

typedef HRESULT (WINAPI *create_fn)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT, const D3D_FEATURE_LEVEL *,
                                     UINT, UINT, ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
typedef HRESULT (WINAPI *compile_fn)(const void *, SIZE_T, const char *, const D3D_SHADER_MACRO *, ID3DInclude *,
                                      const char *, const char *, UINT, UINT, ID3DBlob **, ID3DBlob **);

static const char hlsl[] =
    "float4 vs(uint id : SV_VertexID) : SV_Position {\n"
    "  float2 uv = float2((id << 1) & 2, id & 2);\n"
    "  return float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);\n"
    "}\n"
    "float4 ps() : SV_Target { return float4(1, 0.5, 0.25, 1); }\n";

int main(int argc, char **argv) {
    out = argc > 1 ? fopen(argv[1], "w") : stdout;
    if (!out) return 2;
    HMODULE d3d11 = LoadLibraryA("d3d11.dll"), dc = LoadLibraryA("d3dcompiler_47.dll");
    create_fn create = d3d11 ? (create_fn)(void *)GetProcAddress(d3d11, "D3D11CreateDevice") : NULL;
    compile_fn compile = dc ? (compile_fn)(void *)GetProcAddress(dc, "D3DCompile") : NULL;
    if (!create || !compile) { say("load", "fail d3d11=%p d3dcompiler=%p", (void *)d3d11, (void *)dc); return 1; }

    ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL; D3D_FEATURE_LEVEL fl;
    HRESULT hr = create(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &dev, &fl, &ctx);
    say("device", "%s hr=0x%08lx fl=0x%x", SUCCEEDED(hr) ? "ok" : "fail", hr, fl);
    if (FAILED(hr)) return 1;

    ID3DBlob *vsb = NULL, *psb = NULL, *err = NULL;
    hr = compile(hlsl, sizeof hlsl - 1, "smoke", NULL, NULL, "vs", "vs_5_0", 0, 0, &vsb, &err);
    HRESULT hr2 = compile(hlsl, sizeof hlsl - 1, "smoke", NULL, NULL, "ps", "ps_5_0", 0, 0, &psb, &err);
    say("compile", "%s vs=0x%08lx ps=0x%08lx", SUCCEEDED(hr) && SUCCEEDED(hr2) ? "ok" : "fail", hr, hr2);
    if (FAILED(hr) || FAILED(hr2)) return 1;

    ID3D11VertexShader *vs = NULL; ID3D11PixelShader *ps = NULL;
    hr = ID3D11Device_CreateVertexShader(dev, ID3D10Blob_GetBufferPointer(vsb), ID3D10Blob_GetBufferSize(vsb), NULL, &vs);
    hr2 = ID3D11Device_CreatePixelShader(dev, ID3D10Blob_GetBufferPointer(psb), ID3D10Blob_GetBufferSize(psb), NULL, &ps);
    say("shaders", "%s 0x%08lx 0x%08lx", SUCCEEDED(hr) && SUCCEEDED(hr2) ? "ok" : "fail", hr, hr2);
    if (FAILED(hr) || FAILED(hr2)) return 1;

    D3D11_TEXTURE2D_DESC td = {64, 64, 1, 1, DXGI_FORMAT_R8G8B8A8_UNORM, {1, 0}, D3D11_USAGE_DEFAULT, D3D11_BIND_RENDER_TARGET, 0, 0};
    ID3D11Texture2D *rt = NULL, *staging = NULL; ID3D11RenderTargetView *rtv = NULL;
    ID3D11Device_CreateTexture2D(dev, &td, NULL, &rt);
    ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)rt, NULL, &rtv);
    td.Usage = D3D11_USAGE_STAGING; td.BindFlags = 0; td.CPUAccessFlags = D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE;
    ID3D11Device_CreateTexture2D(dev, &td, NULL, &staging);

    float clear[4] = {0, 0, 0, 0};
    D3D11_VIEWPORT vp = {0, 0, 64, 64, 0, 1};
    ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, clear);
    ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, NULL);
    ID3D11DeviceContext_RSSetViewports(ctx, 1, &vp);
    ID3D11DeviceContext_IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    ID3D11DeviceContext_VSSetShader(ctx, vs, NULL, 0);
    ID3D11DeviceContext_PSSetShader(ctx, ps, NULL, 0);

    D3D11_QUERY_DESC qd = {D3D11_QUERY_OCCLUSION, 0};
    ID3D11Query *q = NULL;
    ID3D11Device_CreateQuery(dev, &qd, &q);
    ID3D11DeviceContext_Begin(ctx, (ID3D11Asynchronous *)q);
    ID3D11DeviceContext_Draw(ctx, 3, 0);
    ID3D11DeviceContext_End(ctx, (ID3D11Asynchronous *)q);

    ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)staging, (ID3D11Resource *)rt);
    D3D11_MAPPED_SUBRESOURCE m;
    hr = ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &m);
    if (SUCCEEDED(hr)) {
        unsigned char *p = (unsigned char *)m.pData + 32 * m.RowPitch + 32 * 4;
        int good = p[0] == 255 && p[1] >= 126 && p[1] <= 129 && p[2] >= 62 && p[2] <= 65 && p[3] == 255;
        say("draw", "%s", good ? "ok" : "wrong");
        say("pixel", "%d,%d,%d,%d", p[0], p[1], p[2], p[3]);
        ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)staging, 0);
    } else say("draw", "fail map=0x%08lx", hr);

    /* Occlusion query: poll up to 5 s. */
    UINT64 samples = 0; DWORD start = GetTickCount();
    while ((hr = ID3D11DeviceContext_GetData(ctx, (ID3D11Asynchronous *)q, &samples, sizeof samples, 0)) == S_FALSE
           && GetTickCount() - start < 5000)
        Sleep(1);
    say("query", "%s hr=0x%08lx samples=%llu", hr == S_OK && samples > 0 ? "ok" : "fail", hr, (unsigned long long)samples);

    /* UpdateSubresource into the STAGING texture, then read it back. */
    say("staging_update", "start");
    static unsigned int pixels[64 * 64];
    for (int i = 0; i < 64 * 64; i++) pixels[i] = 0xff00ff00;
    ID3D11DeviceContext_UpdateSubresource(ctx, (ID3D11Resource *)staging, 0, NULL, pixels, 64 * 4, 0);
    hr = ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &m);
    if (SUCCEEDED(hr)) {
        unsigned int v = *(unsigned int *)((unsigned char *)m.pData + 10 * m.RowPitch + 10 * 4);
        say("staging_update", "%s value=0x%08x", v == 0xff00ff00 ? "ok" : "wrong", v);
        ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)staging, 0);
    } else say("staging_update", "fail map=0x%08lx", hr);

    say("done", "1");
    return 0;
}
