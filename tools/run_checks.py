"""Run existing pure C regression checks. No SDK, device, network or account access."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--cc", required=True, help="Host C compiler (clang.exe on Windows)")
    p.add_argument("--temp-dir", type=Path, help="Optional writable build parent outside repository")
    a = p.parse_args()
    result = {}
    # The Windows cross-toolchain linker may not share access to a sandbox TEMP.
    # Keep disposable native outputs beside, never inside, the public tree.
    parent = (a.temp_dir or ROOT.parent).resolve()
    if parent == ROOT or ROOT in parent.parents:
        p.error("Native test outputs must be outside the public repository")
    with tempfile.TemporaryDirectory(prefix="botw-adapter-checks-", dir=parent) as d:
        for name in ("inventory_detector", "menu_tracker", "motion_math", "touch_geometry", "pacing_policy"):
            exe = Path(d) / (name + ".exe")
            c = subprocess.run([a.cc, "-O2", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT / "src"), str(ROOT / "tests" / ("test_botw_" + name + ".c")), "-o", str(exe)], capture_output=True, text=True)
            if c.returncode:
                raise RuntimeError(c.stdout + c.stderr)
            r = subprocess.run([str(exe)], check=True, capture_output=True, text=True)
            result[name] = json.loads(r.stdout)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
