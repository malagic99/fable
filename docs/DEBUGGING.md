# Debugging a game that won't run — the short playbook

From "it crashes" to a root cause, in the order that usually works. Written
so a person new to Wine — or a small model — can follow it step by step. The
fixes themselves live in [wine-quirks.md](wine-quirks.md); background in
[ARCHITECTURE.md](ARCHITECTURE.md). A deeper guide will follow; this is the
working minimum.

## 1. Read what you already have

- **Fable's per-launch log:** `~/Library/Application Support/Fable/Logs/<Bottle>-<Game>-<date>.log`.
  Look for `wine: Unhandled page fault`, `err:module`, `failed to initialize`,
  `winediag`. Ignore the `hid` and MoltenVK extension lists.
- **Fable Doctor** (the game's banner) already matches known signatures —
  check it first.
- **Unreal games** write their own crash report:
  `drive_c/users/<you>/AppData/Local/<Publisher>/<Game>/Saved/Crashes/UECC-*/`.
  `CrashContext.runtime-xml` has the error message; `UEMinidump.dmp` has the
  faulting thread, registers, and the module list.

## 2. Classify the crash before chasing it

| Where it dies | Usually means |
|---|---|
| Before any game DLL loads, in memory no module owns | DRM/anti-tamper (Denuvo) failing on this Wine build |
| `err:module` … `not found` / `c0000135` | A missing DLL or a broken override |
| Right after `d3d12.dll` / `dxgi.dll` load | The renderer: D3DMetal pairing, framework path, library layout |
| On a worker thread just as a movie starts | Media decoding (GStreamer / Media Foundation) |
| Only when started through Steam | The environment Steam passes to its children |

The address tells you a lot: `0x14…` is usually the game's `.exe`,
`0x6fff…` Wine's Windows-side DLLs, `0x7ff…` or `0x2…` host (macOS)
libraries. `rip=0` means something called a null function pointer — find who
called it (the return address at `rsp`).

## 3. Reproduce safely — never on the real bottle

Clone the bottle with APFS (instant, shares disk blocks):

```bash
cp -cR "<bottle>/prefix" "<scratch>/clone-pfx"
```

Run the game by hand against the clone with the same environment Fable uses
(`GameLauncher.composeLaunchPlan` is the source of truth). Testing another Wine
build upgrades the prefix — that's why the clone exists.

## 4. Turn on the right trace channels

`WINEDEBUG` channels, one or two at a time (logs get huge):

- `+seh` — every exception with registers; find the first `c0000005`.
- `+loaddll` — which DLL loaded last before the crash, builtin or native.
- `warn+module` — failed `GetProcAddress` lookups (a missing export).
- `+ntdll` / `+virtual` — system queries and memory maps (heavy).

Then read only the crashing thread: take the thread id from the
`dispatch_exception` line and filter the log to it.

## 5. Map a host address to its library

While the crash dialog is up, `vmmap <pid>` lists every mapping. Find the
range that contains the address — it names the dylib or `.so`.

## 6. Bisect the environment

When something works under another launcher (Sikarugir, CrossOver) but not
under Fable, capture that launcher's real environment with
`ps -E -ww -p <pid>`, then add its variables to a plain-shell run one at a
time until the failure flips. That's how a single required variable gets
found in minutes instead of days.

## 7. Write it down

Every fix gets a row in [wine-quirks.md](wine-quirks.md) (symptom → fix →
where it lives) and a doc comment at the constant. A diagnosis worth keeping
becomes a Fable Doctor rule.

## Worked example: Ace Combat 8 (Nov 2026)

Four separate layers, each found with the steps above:

1. **Step 2:** a page fault at `0x27F0…` with no game DLL loaded yet → Denuvo.
   Retrying on another Wine build in a clone (step 3) showed Wine 11 passes.
2. **Step 6:** Sikarugir's Wine 11 engine killed every child process; bisecting
   its launcher's environment found the one variable it needs.
3. **Steps 1 and 5:** `rip=0` inside D3DMetal's `d3d12.so`; the renderer's
   libraries had been copied instead of kept as symlinks.
4. **Steps 1 and 4:** a crash at Start Game, `winediag` said
   `GStreamer doesn't support H.264` → the bundled GStreamer wasn't on the
   library path.
