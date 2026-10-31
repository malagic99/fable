/* Fable's native Steam bridge — a stand-in for a running Windows Steam.
 *
 * A game's steam_api(64).dll finds "Steam" through the registry, then loads
 * the steamclient DLL named there. This shim writes those keys pointing at
 * the folder it lives in (where Fable puts the bridge's steamclient DLLs),
 * stays alive as the running Steam process, launches the game in its own
 * folder, and returns the game's exit code.
 *
 * Its own folder — never a real Windows Steam install — so a bottle that
 * also has Windows Steam keeps working.
 *
 * Usage: steam.exe <C:\path\to\game.exe> [game args...] */
#include <windows.h>
#include <stdio.h>

static void set_sz(const wchar_t *key, const wchar_t *name, const wchar_t *value)
{
    RegSetKeyValueW(HKEY_CURRENT_USER, key, name, REG_SZ, value,
                    (DWORD)((wcslen(value) + 1) * sizeof(wchar_t)));
}

int wmain(int argc, wchar_t **argv)
{
    if (argc < 2) {
        fwprintf(stderr, L"usage: steam.exe <game.exe> [args]\n");
        return 2;
    }

    wchar_t dir[MAX_PATH], path[MAX_PATH];
    GetModuleFileNameW(NULL, dir, MAX_PATH);
    wchar_t *slash = wcsrchr(dir, L'\\');
    if (slash) *slash = 0;

    const wchar_t *active = L"Software\\Valve\\Steam\\ActiveProcess";
    DWORD pid = GetCurrentProcessId();
    RegSetKeyValueW(HKEY_CURRENT_USER, active, L"pid", REG_DWORD, &pid, sizeof(pid));
    swprintf(path, MAX_PATH, L"%ls\\steamclient.dll", dir);
    set_sz(active, L"SteamClientDll", path);
    swprintf(path, MAX_PATH, L"%ls\\steamclient64.dll", dir);
    set_sz(active, L"SteamClientDll64", path);
    set_sz(L"Software\\Valve\\Steam", L"SteamPath", dir);
    swprintf(path, MAX_PATH, L"%ls\\steam.exe", dir);
    set_sz(L"Software\\Valve\\Steam", L"SteamExe", path);
    SetEnvironmentVariableW(L"SteamPath", dir);

    /* Command line: the game, then any arguments, each quoted. */
    static wchar_t cmd[32768];
    cmd[0] = 0;
    for (int i = 1; i < argc; i++) {
        if (wcslen(cmd) + wcslen(argv[i]) + 4 >= sizeof(cmd) / sizeof(*cmd)) break;
        wcscat(cmd, L"\"");
        wcscat(cmd, argv[i]);
        wcscat(cmd, L"\" ");
    }

    /* Games load assets relative to their own folder. */
    wchar_t game_dir[MAX_PATH];
    wcsncpy(game_dir, argv[1], MAX_PATH - 1);
    game_dir[MAX_PATH - 1] = 0;
    wchar_t *game_slash = wcsrchr(game_dir, L'\\');
    if (game_slash) *game_slash = 0;

    wprintf(L"fable steam shim: pid %lu, launching %ls\n", pid, argv[1]);
    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(argv[1], cmd, NULL, NULL, FALSE, 0, NULL,
                        game_slash ? game_dir : NULL, &si, &pi)) {
        fwprintf(stderr, L"fable steam shim: CreateProcess failed: %lu\n", GetLastError());
        return 3;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    wprintf(L"fable steam shim: game exited with %lu\n", code);
    return (int)code;
}
