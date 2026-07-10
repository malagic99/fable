# .NET Framework launchers on the free stack (GPTK + real .NET 4.8)

The story of getting Windows **.NET Framework** launcher apps — WPF, .NET
Remoting IPC, 32-bit installers — running under Fable, and the one component
that stands between "almost" and "done." Test subject: Battlestate's Escape
from Tarkov (BSG) launcher, 2026-07-10.

## The wall
The BSG launcher (`.NET Framework 4.6.2`, WPF, CefSharp) crashes in its
single-instance guard: `Microsoft.Shell.SingleInstance<T>` →
`System.Runtime.Remoting.Channels.Ipc.IpcServerChannel`. On Fable's
Sikarugir/default wines it can't even *marshal* the channel handle
(`CriticalHandle … must have a StructLayout attribute`). This is a whole
class — any WPF launcher using single-instance IPC, .NET Remoting, or a
32-bit .NET Framework installer hits it.

## The lever: `x86_32on64-unix`
macOS has no 32-bit runtime. Apple's Game Porting Toolkit wine ships a
**32-on-64 thunking layer** (`lib/wine/x86_32on64-unix`) that runs 32-bit
x86 Windows code anyway. Upstream WineHQ dropped it. So:

| Fable wine | modern? | 32-on-64? |
|---|---|---|
| default (11.10) | ✓ wine-11 | ✗ WoW64 only |
| Sikarugir | ✓ wine-10 | ✗ experimental-WoW64 |
| **GPTK** (`gptk/4.0-heroic`) | ✗ **wine-7.7** | ✓ **has 32-on-64** |
| from-source wine-crossover (`build/…/dist`) | ✓ wine-11.0 | ✗ built x86_64-only |

## What we proved (all empirical, this Mac)
1. **GPTK's 32-on-64 installs real Microsoft .NET Framework 4.8 to
   completion** where every WoW64 wine aborts instantly. Verified:
   `HKLM\…\NDP\v4\Full` `Release=0x80eb1 (528049)`, `Version=4.8.03761`.
2. On GPTK the launcher clears the marshalling crash entirely and reaches
   the *security* stage of the real IPC channel.

### Install recipe (reproducible)
```
GPTK=~/…/Fable/Components/gptk/4.0-heroic/Contents/Resources/wine
export WINEPREFIX=<scratch>  ROSETTA_ADVERTISE_AVX=1
export DYLD_FALLBACK_LIBRARY_PATH="$GPTK/lib/external:$GPTK/lib:/usr/lib"
$GPTK/bin/wine64 wineboot --init
$GPTK/bin/wine64 reg delete "HKLM\\…\\NDP\\v4" /f      # else installer skips on Mono's 4.7
$GPTK/bin/wine64 reg add "HKCU\\Software\\Wine" /v Version /d win7 /f
WINEDLLOVERRIDES="mscoree=d;mshtml=" \
  $GPTK/bin/wine64 NDP48-x86-x64-AllOS-ENU.exe /q /norestart    # mscorsvw ~4 min
```

## The ladder (BSG launcher)
| Stack | Reaches |
|---|---|
| Sikarugir/default (WoW64) | ✗ `CriticalHandle StructLayout` — can't marshal |
| GPTK + Wine Mono 7.4.1 | ⏩ past marshal → `RemotingException: channel not securable` |
| GPTK + real .NET 4.8 (Mono core) | ⏩⏩ real IpcPort runs → `WindowsIdentity.GetCurrent()` SecurityException |
| GPTK + real .NET 4.8 (mscoree=native) | ✗ `c0000135` — real shim won't bootstrap on wine-7.7 |

Two walls, both traced to **GPTK being wine-7.7**:
- **Mono core:** runs real .NET's Remoting.dll (from GAC) but Mono's
  `WindowsIdentity.GetCurrent()` can't mint a Windows token under Wine.
- **Real .NET core:** the mscoree→mscoreei→clr shim won't initialize on the
  old wine (`c0000135`).

## What we need to finish the journey
**One component: a wine build that is BOTH modern (10/11) AND has 32-on-64.**
That single combo clears both walls — modern enough for the real .NET shim to
bootstrap, 32-on-64 so the installer runs. It's exactly what CrossOver ships
(their fork), and the only free piece Fable doesn't have yet.

Concrete routes, best first:
1. **Rebuild wine-crossover WITH 32-on-64 enabled.** The source
   (`crossover-sources-26.2.0`) and our build harness (`build/wine-crossover/`)
   already exist — the current `dist` was configured x86_64-only. CrossOver's
   source *does* support the Mac 32-on-64 path (it's how CX runs this
   launcher). Rebuild with that config → modern wine + 32-on-64. Highest
   confidence; multi-hour finicky build. See `build/wine-crossover/NEXT-SESSION.md`.
2. **A newer Apple GPTK** on a modern wine base that keeps 32-on-64, if Apple
   ships one.
3. **Fix Mono's `WindowsIdentity.GetCurrent()` under Wine** — narrower,
   targets only the mixed-config wall; upstream wine-mono work, uncertain.

## Bankable NOW (ships independent of the launcher)
Fable can install real .NET Framework 4.8 via the GPTK backend and run the
large class of .NET Framework apps/launchers that DON'T hinge on
single-instance IPC + Windows-token security. Productization (see ROADMAP
1.x): Smart Bottle detects a .NET-Framework WPF launcher (or Doctor sees the
IPC crash) → route to GPTK backend + one-click real-.NET-4.8. Sikarugir/WoW64
physically cannot do this.

A scratch prefix with real .NET 4.8 already installed is preserved at
`~/Library/Application Support/Fable/scratch-gptk-prefix` as the working
artifact / next-attempt base.
