"""Rebuild own v10 modules with a user-provided Windows iOS toolchain and SDK.

The pinned headers are intentionally not regenerated for arbitrary hosts.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def command(args):
    r = subprocess.run([str(x) for x in args], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
    if r.returncode:
        raise RuntimeError(r.stdout + r.stderr)
    return r.stdout


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--toolchain-bin", type=Path, required=True, help="Directory containing clang.exe and lld.exe")
    p.add_argument("--sdk", type=Path, required=True, help="Locally licensed iPhoneOS26.5.sdk")
    p.add_argument("--host-ipa", type=Path, required=True, help="Private compatible IPA; host SHA is checked")
    p.add_argument("--out", type=Path, required=True, help="New build directory outside repository")
    a = p.parse_args()
    tc, sdk, out = a.toolchain_bin.resolve(), a.sdk.resolve(), a.out.resolve()
    if out == ROOT or ROOT in out.parents or out.exists():
        p.error("Use a new build directory outside the public repository")
    manifest = json.loads((ROOT / "update-kit-v10/manifest.json").read_text())
    with zipfile.ZipFile(a.host_ipa) as z:
        host = z.read("Payload/TOTK.app/TOTK")
    if hashlib.sha256(host).hexdigest() != manifest["host_executable_sha256"]:
        raise ValueError("Pinned host mismatch; do not transplant guards to a different runtime")
    out.mkdir(parents=True)
    args = [tc / "clang.exe", "-target", "arm64-apple-ios26.0", "-isysroot", sdk, "-I", ROOT / "compat", "-I", ROOT / "src",
            "-F", sdk / "System/Library/SubFrameworks", "-fobjc-arc", "-fblocks", "-O2", "-Wall", "-Wextra", "-Werror", "-Wno-deprecated-declarations"]
    modules = (
        ("BotWInventoryProbe", "botw_ipad_v10.m", ["UIKit", "Foundation", "QuartzCore", "CoreGraphics", "Metal", "CoreMotion"]),
        ("BotWTouchLayout", "botw_touch_layout.m", ["UIKit", "Foundation", "QuartzCore", "CoreGraphics"]),
        ("BotWDisplay", "botw_ipad_display.m", ["UIKit", "Foundation", "QuartzCore", "CoreGraphics", "Metal"]),
    )
    results = {}
    for name, source, frameworks in modules:
        obj, lib = out / (name + ".o"), out / (name + ".dylib")
        command(args + ["-c", ROOT / "src" / source, "-o", obj])
        link = [tc / "lld.exe", "-flavor", "darwin", "-arch", "arm64", "-platform_version", "ios", "26.0", "26.5", "-dylib",
                "-no_adhoc_codesign", "-install_name", "@executable_path/Frameworks/" + name + ".dylib", "-syslibroot", sdk,
                "-F", sdk / "System/Library/Frameworks", "-F", sdk / "System/Library/SubFrameworks", "-L", sdk / "usr/lib", "-o", lib, obj, "-lSystem", "-lobjc"]
        for framework in frameworks:
            link += ["-framework", framework]
        command(link)
        analysis = out / (name + "-analysis.plist")
        command(args + ["--analyze", ROOT / "src" / source, "-Xanalyzer", "-analyzer-output=plist", "-o", analysis])
        count = len(plistlib.loads(analysis.read_bytes()).get("diagnostics", []))
        if count:
            raise ValueError("Analyzer diagnostics in " + name)
        results[name] = {"sha256": hashlib.sha256(lib.read_bytes()).hexdigest(), "static_analysis_diagnostics": count, "unsigned": True}
    # Complete a separate rebuilt kit; never overwrite the archived tested binaries.
    kit = out / "update-kit-v10"
    shutil.copytree(ROOT / "update-kit-v10", kit)
    for name, _, _ in modules:
        shutil.copy2(out / (name + ".dylib"), kit / "Frameworks" / (name + ".dylib"))
    for relative in manifest["files"]:
        manifest["files"][relative] = hashlib.sha256((kit / relative).read_bytes()).hexdigest()
    manifest["rebuilt_locally"] = True
    (kit / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (out / "build-report.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
