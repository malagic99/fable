#!/usr/bin/env python3
"""
gptk4_heroic_patch.py — one-click injection of Game Porting Toolkit 4 into the
CrossOver install that Heroic Games Launcher uses as its runner.

This automates "Method B (manual injection)" from Andrew Tsai's GPTK4 / Heroic /
CrossOver "Golden Gate" guide. Because Heroic drives your CrossOver install,
swapping CrossOver's bundled `apple_gptk` for GPTK 4 means Heroic picks it up for
free — no CrossOver 27.x required.

What it does:
  1. Locates the GPTK 4 evaluation libraries (mounted DMG or extracted folder).
  2. Stages them, renaming nvngx-on-metalfx.{so,dll} -> nvngx.{so,dll}.
  3. Backs up CrossOver's stock apple_gptk -> apple_gptk.backup (once).
  4. Installs the GPTK 4 external/ + wine/ trees into apple_gptk.
  5. Strips com.apple.quarantine so the fresh dylibs don't get SIGKILLed.
  6. (optional) Injects the DLSS shim (nvngx.dll + nvapi64.dll) into a bottle's
     system32 and writes the env vars into that bottle's cxbottle.conf.
  7. Prints the Heroic + Metal-HUD verification steps.

Stdlib only. Tested against CrossOver 26.2 and "Evaluation environment for
Windows games 4.0 beta 1". Run with --revert to restore stock.

Examples:
  ./gptk4_heroic_patch.py                       # auto-detect mounted GPTK 4 DMG, patch CrossOver
  ./gptk4_heroic_patch.py --gptk-dmg ~/Downloads/Game_Porting_Toolkit_4.0.dmg
  ./gptk4_heroic_patch.py --bottle Crossover --metalfx --dxr   # also wire DLSS into a bottle
  ./gptk4_heroic_patch.py --dry-run             # show what would happen, touch nothing
  ./gptk4_heroic_patch.py --revert              # restore apple_gptk.backup
"""

import argparse
import os
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time

# --- terminal niceties -------------------------------------------------------

def _c(code, s):
    return s if not sys.stdout.isatty() else "\033[%sm%s\033[0m" % (code, s)

def info(s):  print(_c("36", "  • ") + s)
def good(s):  print(_c("32", "  ✓ ") + s)
def warn(s):  print(_c("33", "  ! ") + s)
def step(s):  print("\n" + _c("1;36", "==> ") + _c("1", s))
def die(s):
    print(_c("1;31", "ERROR: ") + s, file=sys.stderr)
    sys.exit(1)

DRY = False

def run(cmd, check=True):
    """Run a command, honouring --dry-run for mutating ones."""
    info("$ " + " ".join(cmd))
    if DRY:
        return 0
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0 and check:
        die("command failed (%d): %s\n%s" % (res.returncode, " ".join(cmd),
                                             res.stderr.strip()))
    return res.returncode

# --- discovery ---------------------------------------------------------------

EVAL_GLOB_HINT = "Evaluation environment for Windows games 4.0"

def find_apple_gptk(cx_app):
    """Return the apple_gptk dir inside CrossOver.app, trying known layouts."""
    base = os.path.join(cx_app, "Contents", "SharedSupport", "CrossOver")
    if not os.path.isdir(base):
        die("Not a CrossOver app (missing %s).\nPass --crossover /path/to/CrossOver.app" % base)
    for rel in ("lib64/apple_gptk", "apple_gptk", "lib/apple_gptk"):
        p = os.path.join(base, rel)
        if os.path.isdir(os.path.join(p, "external")) and os.path.isdir(os.path.join(p, "wine")):
            return p
    # Fall back: any apple_gptk holding external/ + wine/
    for root, dirs, _ in os.walk(base):
        if os.path.basename(root) == "apple_gptk" and \
           os.path.isdir(os.path.join(root, "external")) and \
           os.path.isdir(os.path.join(root, "wine")):
            return root
        if root.count(os.sep) - base.count(os.sep) > 4:
            dirs[:] = []
    die("Could not find apple_gptk inside CrossOver. CrossOver may be too old/new "
        "for this layout — check Contents/SharedSupport/CrossOver/.")

def mount_dmg(dmg):
    """Attach a DMG read-only/nobrowse. Return list of mounted mountpoints."""
    info("Mounting %s" % dmg)
    if DRY:
        return []
    res = subprocess.run(
        ["hdiutil", "attach", dmg, "-nobrowse", "-readonly", "-plist"],
        capture_output=True, text=True)
    if res.returncode != 0:
        die("Failed to mount %s\n%s" % (dmg, res.stderr.strip()))
    try:
        plist = plistlib.loads(res.stdout.encode())
    except Exception as e:
        die("Could not parse hdiutil output for %s: %s" % (dmg, e))
    points = [e["mount-point"] for e in plist.get("system-entities", [])
              if e.get("mount-point")]
    return points

def detach(mountpoint):
    subprocess.run(["hdiutil", "detach", mountpoint, "-quiet"],
                   capture_output=True, text=True)

def locate_lib_dir(args, mounts):
    """
    Resolve the GPTK 4 `redist/lib` dir (containing external/ + wine/).
    Handles: explicit --gptk-lib, explicit --gptk-dmg (outer or inner),
    or an already-mounted evaluation volume.
    """
    def lib_under(path):
        for cand in (os.path.join(path, "redist", "lib"), path):
            if os.path.isdir(os.path.join(cand, "external")) and \
               os.path.isdir(os.path.join(cand, "wine")):
                return cand
        return None

    # 1. Explicit extracted lib folder.
    if args.gptk_lib:
        lib = lib_under(args.gptk_lib)
        if not lib:
            die("--gptk-lib %s has no external/ + wine/ (or redist/lib)" % args.gptk_lib)
        return lib

    # 2. Explicit DMG (possibly the outer GPTK dmg holding the inner eval dmg).
    if args.gptk_dmg:
        if not os.path.exists(args.gptk_dmg):
            die("--gptk-dmg not found: %s" % args.gptk_dmg)
        pts = mount_dmg(args.gptk_dmg)
        mounts.extend(pts)
        for p in pts:
            lib = lib_under(p)
            if lib:
                return lib
            # Outer dmg: descend into a nested eval DMG.
            for entry in sorted(os.listdir(p)):
                if entry.lower().endswith(".dmg") and "evaluation" in entry.lower():
                    inner = os.path.join(p, entry)
                    ipts = mount_dmg(inner)
                    mounts.extend(ipts)
                    for ip in ipts:
                        lib = lib_under(ip)
                        if lib:
                            return lib
        die("Mounted %s but found no redist/lib with external/ + wine/." % args.gptk_dmg)

    # 3. Already-mounted evaluation volume.
    for v in sorted(os.listdir("/Volumes")):
        if EVAL_GLOB_HINT.lower() in v.lower():
            lib = lib_under(os.path.join("/Volumes", v))
            if lib:
                info("Using already-mounted volume: /Volumes/%s" % v)
                return lib

    die("Could not find GPTK 4 libraries.\n"
        "  Mount Game_Porting_Toolkit_4.0.dmg (and its inner 'Evaluation\n"
        "  environment for Windows games 4.0' dmg), or pass --gptk-dmg /path.dmg")

# --- core actions ------------------------------------------------------------

def quit_crossover():
    info("Quitting CrossOver and wine processes")
    if DRY:
        return
    subprocess.run(["osascript", "-e", 'quit app "CrossOver"'],
                   capture_output=True, text=True)
    time.sleep(1)
    for pat in ("CrossOver", "wineserver", "wine64", "wine-preloader"):
        subprocess.run(["pkill", "-f", pat], capture_output=True, text=True)
    time.sleep(1)

def stage_libs(lib_dir, staging):
    """Copy external/ + wine/ into staging and apply the nvngx renames."""
    for sub in ("external", "wine"):
        src = os.path.join(lib_dir, sub)
        dst = os.path.join(staging, sub)
        info("Staging %s/" % sub)
        if not DRY:
            shutil.copytree(src, dst, symlinks=True)

    renames = [
        ("wine/x86_64-unix/nvngx-on-metalfx.so",     "wine/x86_64-unix/nvngx.so"),
        ("wine/x86_64-windows/nvngx-on-metalfx.dll", "wine/x86_64-windows/nvngx.dll"),
    ]
    for src_rel, dst_rel in renames:
        src = os.path.join(staging, src_rel)
        dst = os.path.join(staging, dst_rel)
        if DRY:
            info("Rename %s -> %s" % (src_rel, dst_rel))
        elif os.path.exists(src):
            os.rename(src, dst)
            good("Renamed %s -> %s" % (os.path.basename(src_rel), os.path.basename(dst_rel)))
        else:
            warn("Expected %s not present (layout may differ) — skipping rename" % src_rel)

APP_MGMT_HELP = """\
EPERM writing inside CrossOver.app — this is macOS App Management protection,
not a file-permission problem. The app/terminal hosting this script needs the
"App Management" (or "Full Disk Access") privacy permission to modify a signed
app bundle in /Applications.

Fix one of these, then re-run:
  • System Settings -> Privacy & Security -> App Management -> enable the app
    that is running this script (e.g. Claude, Terminal, or iTerm), then fully
    quit and reopen that app.
  • Or run this script with sudo from your own Terminal:
        sudo python3 %s --crossover /Applications/CrossOver.app
    (root bypasses App Management. Note: run the --bottle wiring WITHOUT sudo
    afterwards so bottle files stay owned by you.)
""" % os.path.abspath(sys.argv[0] if sys.argv and sys.argv[0] else __file__)

def _guard_bundle_write(fn, *a, **kw):
    try:
        return fn(*a, **kw)
    except PermissionError:
        die(APP_MGMT_HELP)

def install_libs(staging, apple_gptk, force):
    backup = apple_gptk + ".backup"
    if os.path.exists(backup):
        if force:
            warn("apple_gptk.backup already exists — leaving the original backup intact")
        else:
            info("apple_gptk.backup already exists (stock preserved from a prior run)")
        # Remove current (already-patched) apple_gptk before reinstalling.
        if not DRY and os.path.isdir(apple_gptk):
            _guard_bundle_write(shutil.rmtree, apple_gptk)
    else:
        info("Backing up stock apple_gptk -> apple_gptk.backup")
        if not DRY:
            _guard_bundle_write(os.rename, apple_gptk, backup)

    info("Installing GPTK 4 into %s" % apple_gptk)
    if not DRY:
        _guard_bundle_write(os.makedirs, apple_gptk, exist_ok=True)
        for sub in ("external", "wine"):
            _guard_bundle_write(shutil.copytree,
                                os.path.join(staging, sub),
                                os.path.join(apple_gptk, sub), symlinks=True)

    info("Stripping com.apple.quarantine (prevents dylib SIGKILL)")
    run(["xattr", "-dr", "com.apple.quarantine", apple_gptk], check=False)

def revert(apple_gptk):
    backup = apple_gptk + ".backup"
    if not os.path.isdir(backup):
        die("No backup at %s — nothing to revert." % backup)
    quit_crossover()
    info("Restoring stock apple_gptk from backup")
    if not DRY:
        if os.path.isdir(apple_gptk):
            shutil.rmtree(apple_gptk)
        os.rename(backup, apple_gptk)
    good("Reverted CrossOver to stock GPTK. Remove any env vars you added to "
         "bottle cxbottle.conf files manually.")

# --- Heroic wine-bundle mode (free, no CrossOver license) --------------------
#
# Targets an open-source wine .app that Heroic uses as a runner (e.g. Gcenx's
# "Game-Porting-Toolkit-latest"). Swaps that build's bundled D3DMetal + d3d/dxgi
# shims for GPTK 4's, in place. Lives in ~/Library, so no App Management block.

HEROIC_WINE_DIR = os.path.expanduser("~/Library/Application Support/heroic/tools/wine")

def resolve_wine_bundle(name_or_path):
    cand = name_or_path
    if not os.path.isdir(cand):
        cand = os.path.join(HEROIC_WINE_DIR, name_or_path)
    if not os.path.isdir(cand):
        avail = []
        if os.path.isdir(HEROIC_WINE_DIR):
            avail = sorted(os.listdir(HEROIC_WINE_DIR))
        die("Wine bundle not found: %s\n  Looked under %s\n  Installed: %s"
            % (name_or_path, HEROIC_WINE_DIR, ", ".join(avail) or "(none)"))
    return cand

def _find_first(root, predicate, want_dir=False):
    for dirpath, dirs, files in os.walk(root):
        names = dirs if want_dir else files
        for n in names:
            p = os.path.join(dirpath, n)
            if predicate(n, p):
                return p
    return None

def find_wine_targets(bundle):
    """
    Inspect a wine bundle and return (mode, ext_dir, unix_dir, win_dir).
    mode 'swap'  -> build already ships D3DMetal (a GPTK build): reliable.
    mode 'fresh' -> no D3DMetal present (plain wine/DXMT/crossover): experimental.
    """
    fw = _find_first(bundle, lambda n, p: n == "D3DMetal.framework", want_dir=True)
    unix = _find_first(bundle, lambda n, p: n == "x86_64-unix" and
                       os.path.exists(os.path.join(p, "d3d12.so")), want_dir=True)
    win = _find_first(bundle, lambda n, p: n == "x86_64-windows" and
                      os.path.exists(os.path.join(p, "d3d12.dll")), want_dir=True)
    if unix is None:
        unix = _find_first(bundle, lambda n, p: n == "x86_64-unix", want_dir=True)
    if win is None:
        win = _find_first(bundle, lambda n, p: n == "x86_64-windows", want_dir=True)
    if not unix or not win:
        die("Doesn't look like a wine build (no x86_64-unix / x86_64-windows under %s)." % bundle)
    if fw:
        return "swap", os.path.dirname(fw), unix, win
    # No D3DMetal yet -> create an external dir beside the unix libs.
    ext = os.path.join(os.path.dirname(os.path.dirname(unix)), "external")
    return "fresh", ext, unix, win

def _snapshot(dst, backup_root, bundle):
    """Copy an existing dst into <bundle>/.gptk4-backup/ preserving rel path (once)."""
    if not os.path.exists(dst):
        return
    rel = os.path.relpath(dst, bundle)
    bdst = os.path.join(backup_root, rel)
    if os.path.exists(bdst):
        return  # original already snapshotted from a prior run
    if DRY:
        return
    os.makedirs(os.path.dirname(bdst), exist_ok=True)
    if os.path.isdir(dst):
        shutil.copytree(dst, bdst, symlinks=True)
    else:
        shutil.copy2(dst, bdst)

def _place(src, dst, backup_root, bundle):
    _snapshot(dst, backup_root, bundle)
    info("  %s -> %s" % (os.path.basename(src), os.path.relpath(dst, bundle)))
    if DRY:
        return
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    elif os.path.exists(dst):
        os.remove(dst)
    if os.path.isdir(src):
        shutil.copytree(src, dst, symlinks=True)
    else:
        shutil.copy2(src, dst)

def inject_into_wine_bundle(bundle, lib_dir, force):
    mode, ext_dir, unix_dir, win_dir = find_wine_targets(bundle)
    backup_root = os.path.join(bundle, ".gptk4-backup")
    if os.path.isdir(backup_root) and not force:
        info("Existing .gptk4-backup found — original is already snapshotted.")

    info("Bundle      : %s" % bundle)
    info("Mode        : %s%s" % (mode, "  (EXPERIMENTAL — build had no D3DMetal)"
                                 if mode == "fresh" else "  (D3DMetal swap)"))
    info("external -> : %s" % ext_dir)
    info("unix     -> : %s" % unix_dir)
    info("windows  -> : %s" % win_dir)

    if not DRY:
        os.makedirs(ext_dir, exist_ok=True)

    step("Swapping D3DMetal framework + libd3dshared")
    for item in ("D3DMetal.framework", "libd3dshared.dylib"):
        src = os.path.join(lib_dir, "external", item)
        if os.path.exists(src) or DRY:
            _place(src, os.path.join(ext_dir, item), backup_root, bundle)

    step("Swapping wine d3d/dxgi/nvngx shims")
    rename = {"nvngx-on-metalfx.so": "nvngx.so", "nvngx-on-metalfx.dll": "nvngx.dll"}
    for side, dst_dir in (("x86_64-unix", unix_dir), ("x86_64-windows", win_dir)):
        srcdir = os.path.join(lib_dir, "wine", side)
        if not os.path.isdir(srcdir):
            continue
        for f in sorted(os.listdir(srcdir)):
            dst_name = rename.get(f, f)
            _place(os.path.join(srcdir, f),
                   os.path.join(dst_dir, dst_name), backup_root, bundle)

    info("Stripping com.apple.quarantine")
    run(["xattr", "-dr", "com.apple.quarantine", ext_dir], check=False)
    run(["xattr", "-dr", "com.apple.quarantine", unix_dir], check=False)
    run(["xattr", "-dr", "com.apple.quarantine", win_dir], check=False)
    good("GPTK 4 injected into wine bundle (backup at %s)." % os.path.relpath(backup_root, bundle))
    return mode, ext_dir

def revert_wine_bundle(bundle):
    backup_root = os.path.join(bundle, ".gptk4-backup")
    if not os.path.isdir(backup_root):
        die("No .gptk4-backup in %s — nothing to revert." % bundle)
    info("Restoring original D3DMetal/shims from %s" % backup_root)
    if not DRY:
        for dirpath, _, files in os.walk(backup_root):
            for f in files:
                src = os.path.join(dirpath, f)
                rel = os.path.relpath(src, backup_root)
                dst = os.path.join(bundle, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                if os.path.exists(dst):
                    os.remove(dst)
                shutil.copy2(src, dst)
    good("Wine bundle reverted to its original D3DMetal. (Backup left in place; "
         "delete .gptk4-backup manually if you want it gone.)")

# --- bottle wiring -----------------------------------------------------------

def resolve_bottle(name_or_path):
    if os.path.isdir(name_or_path) and os.path.exists(os.path.join(name_or_path, "cxbottle.conf")):
        return name_or_path
    p = os.path.expanduser("~/Library/Application Support/CrossOver/Bottles/%s" % name_or_path)
    if os.path.isdir(p):
        return p
    die("Bottle not found: %s\n  Looked in ~/Library/Application Support/CrossOver/Bottles/" % name_or_path)

def inject_dlss_shim(bottle, staging, env_pairs):
    sys32 = os.path.join(bottle, "drive_c", "windows", "system32")
    if not os.path.isdir(sys32):
        die("Bottle has no drive_c/windows/system32: %s" % bottle)
    for dll in ("nvngx.dll", "nvapi64.dll"):
        src = os.path.join(staging, "wine", "x86_64-windows", dll)
        if not os.path.exists(src) and not DRY:
            warn("%s not in staged libs — skipping DLSS shim copy" % dll)
            continue
        info("Copying %s -> bottle system32" % dll)
        if not DRY:
            shutil.copy2(src, os.path.join(sys32, dll))
    write_cxbottle_env(os.path.join(bottle, "cxbottle.conf"), env_pairs)

def write_cxbottle_env(conf_path, env_pairs):
    """Merge env_pairs into the [EnvironmentVariables] section of cxbottle.conf,
    preserving the rest of the file and existing variables."""
    info("Writing env vars into %s" % os.path.basename(conf_path))
    for k, v in env_pairs:
        info('    "%s" = "%s"' % (k, v))
    if DRY:
        return

    lines = []
    if os.path.exists(conf_path):
        with open(conf_path, "r") as f:
            lines = f.read().splitlines()

    # Find [EnvironmentVariables] section bounds.
    sec_start = None
    for i, ln in enumerate(lines):
        if ln.strip().lower() == "[environmentvariables]":
            sec_start = i
            break

    def fmt(k, v):
        return '"%s" = "%s"' % (k, v)

    if sec_start is None:
        if lines and lines[-1].strip() != "":
            lines.append("")
        lines.append("[EnvironmentVariables]")
        for k, v in env_pairs:
            lines.append(fmt(k, v))
    else:
        # Section end = next "[...]" header or EOF.
        sec_end = len(lines)
        for j in range(sec_start + 1, len(lines)):
            if lines[j].strip().startswith("[") and lines[j].strip().endswith("]"):
                sec_end = j
                break
        body = lines[sec_start + 1:sec_end]
        for k, v in env_pairs:
            replaced = False
            for j, bl in enumerate(body):
                key = bl.split("=", 1)[0].strip().strip('"').strip()
                if key.lower() == k.lower():
                    body[j] = fmt(k, v)
                    replaced = True
                    break
            if not replaced:
                body.append(fmt(k, v))
        lines = lines[:sec_start + 1] + body + lines[sec_end:]

    # Atomic-ish write with a .bak alongside.
    shutil.copy2(conf_path, conf_path + ".bak") if os.path.exists(conf_path) else None
    with open(conf_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    good("Updated %s (backup at cxbottle.conf.bak)" % conf_path)

# --- main --------------------------------------------------------------------

def main():
    global DRY
    ap = argparse.ArgumentParser(
        description="Inject Game Porting Toolkit 4 into CrossOver for Heroic.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    ap.add_argument("--crossover", default="/Applications/CrossOver.app",
                    help="Path to CrossOver.app (default: /Applications/CrossOver.app)")
    ap.add_argument("--gptk-dmg", help="Path to Game_Porting_Toolkit_4.0.dmg (or the inner eval dmg)")
    ap.add_argument("--gptk-lib", help="Path to an already-extracted GPTK redist/lib folder")
    ap.add_argument("--wine-bundle",
                    help="Target a free Heroic wine .app instead of CrossOver "
                         "(name under heroic/tools/wine, or an absolute path). "
                         "Swaps that build's D3DMetal for GPTK 4 — free, no license.")
    ap.add_argument("--bottle", help="Bottle name or path to also receive the DLSS shim + env vars")
    ap.add_argument("--metalfx", action="store_true", help="Add D3DM_ENABLE_METALFX=1 to the bottle")
    ap.add_argument("--dxr", action="store_true", help="Add D3DM_SUPPORT_DXR=1 (DirectX Raytracing)")
    ap.add_argument("--no-avx", action="store_true", help="Do NOT add ROSETTA_ADVERTISE_AVX=1")
    ap.add_argument("--revert", action="store_true", help="Restore apple_gptk.backup and exit")
    ap.add_argument("--force", action="store_true", help="Proceed even if a backup already exists")
    ap.add_argument("--yes", action="store_true", help="Skip the confirmation prompt")
    ap.add_argument("--dry-run", action="store_true", help="Show actions without changing anything")
    args = ap.parse_args()

    DRY = args.dry_run

    # Preflight.
    if platform.system() != "Darwin":
        die("This script is macOS-only.")
    if platform.machine() != "arm64":
        warn("Not arm64 — D3DMetal/GPTK is Apple-silicon only. Continuing anyway.")
    if os.geteuid() == 0:
        warn("Running as root; files will be owned by root. Usually run as your user.")

    # ---- Free path: inject into a Heroic wine bundle instead of CrossOver ----
    if args.wine_bundle:
        bundle = resolve_wine_bundle(args.wine_bundle)
        if args.revert:
            revert_wine_bundle(bundle)
            return
        mounts = []
        staging_root = None
        try:
            lib_dir = locate_lib_dir(args, mounts)
            good("GPTK 4 libraries: %s" % lib_dir)
            print()
            step("Plan (free wine-bundle mode)")
            print("    Wine bundle  : %s" % bundle)
            print("    GPTK 4 source: %s" % lib_dir)
            mode, _, _, _ = find_wine_targets(bundle)
            if mode == "fresh":
                warn("This build ships NO D3DMetal — EXPERIMENTAL. A plain wine/DXMT "
                     "build may not load injected D3DMetal without extra wiring.")
            if DRY:
                print("    (dry run — nothing will be written)")
            if not args.yes and not DRY:
                ans = input("\nProceed? [y/N] ").strip().lower()
                if ans not in ("y", "yes"):
                    die("Aborted.")
            quit_crossover()
            staging_root = tempfile.mkdtemp(prefix="gptk4_stage_")
            stage_libs(lib_dir, staging_root)
            mode, ext_dir = inject_into_wine_bundle(bundle, staging_root, args.force)
        finally:
            if staging_root and os.path.isdir(staging_root) and not DRY:
                shutil.rmtree(staging_root, ignore_errors=True)
            for m in reversed(mounts):
                detach(m)

        step("Wire it into Heroic")
        envs = ["WINEMSYNC=1"]
        if args.metalfx: envs.append("D3DM_ENABLE_METALFX=1")
        if args.dxr:     envs.append("D3DM_SUPPORT_DXR=1")
        if not args.no_avx: envs.append("ROSETTA_ADVERTISE_AVX=1")
        if mode == "fresh":
            envs.append('WINEDLLOVERRIDES=d3d12,d3d12core,dxgi=b')
            envs.append('DYLD_FALLBACK_LIBRARY_PATH=%s' % ext_dir)
        print("""  1. Heroic -> game -> Settings -> Wine version: select '%s'.
  2. Enable D3DMetal (graphics toggle). A GPTK build defaults to it.
  3. Heroic -> game -> Settings -> Advanced -> Environment Variables, add:
%s
  4. Verify (Metal HUD should read 'Game Porting Toolkit 4'):
       launchctl setenv MTL_HUD_ENABLED 1
       # launch game, then:
       launchctl unsetenv MTL_HUD_ENABLED

  Revert this bundle:  %s --wine-bundle '%s' --revert"""
              % (os.path.basename(bundle),
                 "\n".join("       " + e for e in envs),
                 os.path.basename(sys.argv[0]), args.wine_bundle))
        good("Done (free path — no CrossOver license needed).")
        return

    apple_gptk = find_apple_gptk(args.crossover)
    info("CrossOver apple_gptk: %s" % apple_gptk)

    if args.revert:
        revert(apple_gptk)
        return

    mounts = []
    staging_root = None
    try:
        lib_dir = locate_lib_dir(args, mounts)
        good("GPTK 4 libraries: %s" % lib_dir)

        bottle = resolve_bottle(args.bottle) if args.bottle else None

        # Confirm.
        print()
        step("Plan")
        print("    Patch CrossOver : %s" % args.crossover)
        print("    GPTK 4 source   : %s" % lib_dir)
        print("    Target apple_gptk: %s" % apple_gptk)
        print("    Backup -> %s.backup" % os.path.basename(apple_gptk))
        if bottle:
            envs = ["WINEMSYNC=1"]
            if args.metalfx: envs.append("D3DM_ENABLE_METALFX=1")
            if args.dxr:     envs.append("D3DM_SUPPORT_DXR=1")
            if not args.no_avx: envs.append("ROSETTA_ADVERTISE_AVX=1")
            print("    DLSS shim -> bottle: %s" % bottle)
            print("    Env vars          : %s" % ", ".join(envs))
        if DRY:
            print("    (dry run — nothing will be written)")
        if not args.yes and not DRY:
            ans = input("\nProceed? [y/N] ").strip().lower()
            if ans not in ("y", "yes"):
                die("Aborted.")

        step("Patching CrossOver")
        quit_crossover()
        staging_root = tempfile.mkdtemp(prefix="gptk4_stage_")
        stage_libs(lib_dir, staging_root)
        install_libs(staging_root, apple_gptk, args.force)
        good("GPTK 4 injected into CrossOver.")

        if bottle:
            step("Wiring DLSS shim + env vars into bottle")
            env_pairs = [("WINEMSYNC", "1")]
            if args.metalfx:
                env_pairs.append(("D3DM_ENABLE_METALFX", "1"))
            if args.dxr:
                env_pairs.append(("D3DM_SUPPORT_DXR", "1"))
            if not args.no_avx:
                env_pairs.append(("ROSETTA_ADVERTISE_AVX", "1"))
            inject_dlss_shim(bottle, staging_root, env_pairs)
            good("Bottle wired.")
    finally:
        if staging_root and os.path.isdir(staging_root) and not DRY:
            shutil.rmtree(staging_root, ignore_errors=True)
        for m in reversed(mounts):
            detach(m)

    # Closing instructions.
    step("Next: wire it into Heroic")
    print("""  1. Heroic -> your game -> Settings.
  2. Runner / Wine version: select CrossOver (the one you just patched).
  3. Bottle/Prefix: point at %s
  4. Enable D3DMetal (graphics-layer toggle). If absent, set in cxbottle.conf:
         "WINED3DMETAL" = "1"
         "WINEDXVK"     = "0"
  5. MetalFX is more reliable via Heroic -> game Settings -> Advanced ->
     Environment Variables  (add  D3DM_ENABLE_METALFX=1  there) than via
     cxbottle.conf when launched through Heroic.""" % (args.bottle or "<your bottle>"))

    step("Verify it's actually GPTK 4")
    print("""  launchctl setenv MTL_HUD_ENABLED 1
  # launch the game from Heroic — the Metal HUD should read "Game Porting Toolkit 4"
  launchctl unsetenv MTL_HUD_ENABLED

  Revert any time:  ./gptk4_heroic_patch.py --revert""")
    good("Done.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        die("Interrupted.")
