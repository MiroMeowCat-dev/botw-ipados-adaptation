"""Verify the curated public tree and nested pure-module ZIP. Offline, read-only."""
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LIBS = {"BotWDisplay.dylib", "BotWInventoryProbe.dylib", "BotWTouchLayout.dylib"}
SUFFIXES = {".md", ".txt", ".m", ".h", ".c", ".py", ".json", ".plist", ".dylib", ".zip"}
ROOT_NAMES = {"LICENSE", ".gitignore", "SHA256SUMS"}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def check(path, data):
    p = Path(path)
    if p.name not in ROOT_NAMES and p.suffix not in SUFFIXES:
        raise ValueError("Not allowlisted: " + path)
    if p.suffix == ".dylib" and (p.name not in LIBS or len(data) > 200000 or data[:4] != bytes.fromhex("cffaedfe")):
        raise ValueError("Unexpected binary: " + path)
    if len(data) > 1024**2:
        raise ValueError("Unexpected large file: " + path)
    if re.search(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", data):
        raise ValueError("Possible personal email: " + path)
    if re.search(rb"C:[/\\]Users[/\\]", data, re.I):
        raise ValueError("Personal Windows path: " + path)
    for marker in (b"-----BEGIN " + b"PRIVATE KEY-----", b"-----BEGIN " + b"RSA PRIVATE KEY-----", b"gh" + b"p_", b"github_" + b"pat_"):
        if marker in data:
            raise ValueError("Possible credential: " + path)


def main():
    files = {}
    for p in sorted(ROOT.rglob("*")):
        if not p.is_file() or ".git" in p.relative_to(ROOT).parts:
            continue
        name = p.relative_to(ROOT).as_posix()
        data = p.read_bytes()
        check(name, data)
        files[name] = digest(data)
        if p.suffix == ".zip":
            with zipfile.ZipFile(p) as z:
                if len(z.namelist()) != len(set(z.namelist())) or z.testzip():
                    raise ValueError("ZIP CRC or duplicate entry error")
                for e in z.infolist():
                    if e.is_dir() or e.filename.startswith("/") or ".." in Path(e.filename).parts or e.file_size > 200000:
                        raise ValueError("Unexpected nested entry")
                    check(e.filename, z.read(e))
    manifest = json.loads((ROOT / "update-kit-v10/manifest.json").read_text())
    for name, expected in manifest["files"].items():
        if digest((ROOT / "update-kit-v10" / name).read_bytes()) != expected:
            raise ValueError("Module manifest mismatch: " + name)
    sums = ROOT / "SHA256SUMS"
    if sums.exists():
        listed = {}
        for line in sums.read_text().splitlines():
            h, name = line.split("  ", 1)
            listed[name] = h
        actual = {k: v for k, v in files.items() if k != "SHA256SUMS"}
        if listed != actual:
            raise ValueError("File manifest does not match complete public tree")
    print(json.dumps({"files": len(files), "bytes": sum((ROOT / n).stat().st_size for n in files),
                      "module_hashes_passed": True, "allowlist_passed": True, "nested_zip_passed": True,
                      "credential_pattern_scan_passed": True, "sha256sums_checked": sums.exists()}, indent=2))


if __name__ == "__main__":
    main()
