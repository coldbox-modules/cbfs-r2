#!/usr/bin/env python3
"""Build a reproducible ForgeBox module ZIP using an explicit source allowlist."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SEMVER = r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?"


def build(output, sdk_version=None, repository=None):
    manifest = json.loads((ROOT / "box.json").read_text())
    version = manifest["version"]
    if not re.fullmatch(SEMVER, version):
        raise ValueError("Package version must be an exact semantic version")
    if sdk_version:
        if manifest["slug"] != "cbfs-r2":
            raise ValueError("SDK version override applies only to cbfs-r2")
        manifest["dependencies"]["r2sdk"] = sdk_version
    for name, dependency in manifest.get("dependencies", {}).items():
        if not re.fullmatch(SEMVER, dependency):
            raise ValueError(f"{name} must use an exact published ForgeBox version, not {dependency!r}")
    if repository:
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
            raise ValueError("Repository must be an owner/name pair")
        url = "https://github.com/" + repository
        manifest.update(homepage=url, documentation=url + "/blob/main/README.md", bugs=url + "/issues",
                        repository={"type": "git", "URL": url})
    manifest.pop("scripts", None)
    manifest.pop("devDependencies", None)
    manifest.pop("installPaths", None)
    manifest["ignore"] = []  # All files have already passed the release allowlist.
    output.mkdir(parents=True, exist_ok=True)
    destination = output / f'{manifest["slug"]}-{version}.zip'
    files = {name: (ROOT / name).read_bytes() for name in
             ("ModuleConfig.cfc", "README.md", "LICENSE", "NOTICE", "CHANGELOG.md", "CONTRIBUTING.md", "SECURITY.md")}
    for directory in ("models", "docs"):
        for path in sorted((ROOT / directory).rglob("*")):
            if path.is_symlink():
                raise ValueError("Symlinks are not allowed in release artifacts")
            if path.is_file() and not any(part.startswith(".") for part in path.relative_to(ROOT).parts):
                files[path.relative_to(ROOT).as_posix()] = path.read_bytes()
    files["box.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    # Keep module metadata aligned with the package descriptor without editing source.
    source = files["ModuleConfig.cfc"].decode()
    source, count = re.subn(r'(this\.version\s*=\s*")[^"]+(";)',
                            lambda m: m[1] + version + m[2], source)
    if count != 1:
        raise ValueError("Expected one module version declaration")
    files["ModuleConfig.cfc"] = source.encode()
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    checksum = hashlib.sha256(destination.read_bytes()).hexdigest()
    (output / (destination.name + ".sha256")).write_text(f"{checksum}  {destination.name}\n")
    (output / "manifest.json").write_text(json.dumps({"package": manifest, "sha256": checksum,
        "files": {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())}}, indent=2) + "\n")
    print(destination)
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".artifacts")
    parser.add_argument("--sdk-version", help="Exact ForgeBox version; publish and verify r2sdk first")
    parser.add_argument("--repository", help="Actual GitHub owner/repository used in package links")
    args = parser.parse_args()
    build(args.output.resolve(), args.sdk_version, args.repository)
