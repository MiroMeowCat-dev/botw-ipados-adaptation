"""Apply the asset-free v10 kit to the exact local v9 Documents-style IPA.

Offline only. Never installs, signs, downloads, or modifies the input file.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "Payload/TOTK.app/"


def sha(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", type=Path, required=True, help="Original unsigned v9 Documents-style IPA, see manifest")
    p.add_argument("--output", type=Path, required=True, help="New unsigned private IPA outside the public repository")
    p.add_argument("--kit", type=Path, default=ROOT / "update-kit-v10")
    a = p.parse_args()
    source, target, kit = a.input.resolve(), a.output.resolve(), a.kit.resolve()
    if target == ROOT or ROOT in target.parents:
        p.error("Write the private IPA outside this public repository")
    if target.exists() or source == target:
        p.error("Output must be new; input is never overwritten")
    manifest = json.loads((kit / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("schema") != 1:
        raise ValueError("Unsupported manifest schema")
    # Intentionally no override: this archive does not claim generic host ABI support.
    if sha(source) != manifest["supported_input_ipa_sha256"]:
        raise ValueError("Unsupported input IPA. Use the privately backed-up v9 input; do not bypass the guard.")
    replacements = {}
    allowed = {"Frameworks/BotWDisplay.dylib", "Frameworks/BotWTouchLayout.dylib", "Frameworks/BotWInventoryProbe.dylib",
               "Settings.bundle/Root.plist", "BotWSettings.json"}
    if set(manifest["files"]) != allowed:
        raise ValueError("Unexpected kit file set")
    for name, digest in manifest["files"].items():
        path = kit / name
        if sha(path) != digest:
            raise ValueError("Kit digest mismatch: " + name)
        replacements[PREFIX + name] = path.read_bytes()
    target.parent.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(target.parent).free < source.stat().st_size + 1024**3:
        raise RuntimeError("Need input-size plus 1 GiB free at destination")
    with zipfile.ZipFile(source) as z:
        names = z.namelist()
        if len(names) != len(set(names)) or z.testzip():
            raise ValueError("Input duplicate entries or CRC failure")
        host = z.read(PREFIX + "TOTK")
        if hashlib.sha256(host).hexdigest() != manifest["host_executable_sha256"]:
            raise ValueError("Incompatible host executable")
        for lib in ("BotWDisplay", "BotWTouchLayout", "BotWInventoryProbe"):
            if ("@executable_path/Frameworks/" + lib + ".dylib").encode() not in host:
                raise ValueError("Host lacks a required module load command")
        info = plistlib.loads(z.read(PREFIX + "Info.plist"))
        info.update(CFBundleDisplayName="塞尔达", CFBundleName="塞尔达", CFBundleVersion=manifest["bundle_version"], CFBundleShortVersionString="1.6.0", LSSupportsGameMode=True)
        replacements[PREFIX + "Info.plist"] = plistlib.dumps(info, fmt=plistlib.FMT_BINARY)
        preserved = {}
        # ZIP32/stored matches the successfully installed small-host route.
        with zipfile.ZipFile(target, "x", zipfile.ZIP_STORED, allowZip64=False) as out:
            for entry in z.infolist():
                if entry.is_dir():
                    continue
                if "_CodeSignature/" in entry.filename or entry.filename.endswith("embedded.mobileprovision"):
                    raise ValueError("Expected an unsigned input, not a personal signed IPA")
                if entry.filename in replacements:
                    continue
                item = zipfile.ZipInfo(entry.filename, entry.date_time)
                item.create_system, item.external_attr = 3, entry.external_attr
                item.file_size = entry.file_size
                with z.open(entry) as src, out.open(item, "w", force_zip64=False) as dst:
                    shutil.copyfileobj(src, dst, 2 * 1024**2)
                preserved[entry.filename] = (entry.file_size, entry.CRC)
            for name, data in replacements.items():
                item = zipfile.ZipInfo(name)
                item.create_system = 3
                item.external_attr = (0o100755 if name.endswith(".dylib") else 0o100644) << 16
                out.writestr(item, data)
    with zipfile.ZipFile(target) as z:
        if len(z.namelist()) != len(set(z.namelist())) or z.testzip():
            raise ValueError("Output duplicate entries or CRC failure")
        for name, expected in preserved.items():
            e = z.getinfo(name)
            if (e.file_size, e.CRC) != expected:
                raise ValueError("Unrelated file changed")
        for name, data in replacements.items():
            if z.read(name) != data:
                raise ValueError("Replacement readback mismatch")
        if z.read(PREFIX + "TOTK") != host:
            raise ValueError("Host changed")
    print(json.dumps({"output": str(target), "bytes": target.stat().st_size, "sha256": sha(target), "all_zip_crcs_passed": True,
                      "host_unchanged": True, "preserved_entries": len(preserved), "unsigned": True}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
