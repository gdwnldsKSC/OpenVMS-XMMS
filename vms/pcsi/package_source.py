#!/usr/bin/env python3
"""Create the source companion for a native XMMS PCSI release.

Supply the exact XMMS tree, patched GTK build sources, and normalized OPL
sources used for the binaries. This tool never changes its inputs and never
overwrites an output. Python is only a release-host requirement.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import zipfile

MANIFEST = "SOURCE_MANIFEST.json"
OMIT_DIRS = {
    ".git", ".svn", ".hg", ".codex", ".agents", ".aws", ".ssh",
    "__pycache__", "cxx_repository", "vms_build", "build", "dist",
    "guest", "media", "artifacts", "logs", "tmp", "temp", "node_modules",
}
OMIT_SUFFIXES = {
    ".o", ".obj", ".exe", ".olb", ".a", ".so", ".dll", ".dylib",
    ".lib", ".pdb", ".ilk", ".exp", ".map", ".lis", ".listing",
    ".pyc", ".pyo", ".class", ".gmo", ".mo", ".pch", ".idb",
    ".res", ".log", ".err", ".out", ".tmp", ".bak", ".sav",
    ".img", ".qcow", ".qcow2", ".vhd", ".vhdx", ".iso", ".pcsi",
    ".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".dmp", ".dump",
    ".wav", ".mp3", ".ogg", ".flac", ".mp4", ".mkv",
}
OMIT_NAMES = {
    "native-results.json", "native-response.json", "native-request.json",
    "cmakecache.txt", "config.log", "config.status", "config.cache",
    "xmms-source-v1_2_11.zip", "source_manifest.json",
}
PRIVATE_NAME = re.compile(
    r"(?:password|credential|secret|private[_-]?key|^id_(?:rsa|dsa|ecdsa|ed25519))",
    re.IGNORECASE,
)
MMOV_SDK_NAMES = {"mme_api.h", "mmbasic.h", "mmsystem.h", "mme_public.h", "mmddk.h", "cmm.h", "cmmmd.h"}
BINARY_SOURCE_ASSETS = {".bmp", ".png", ".gif", ".jpg", ".jpeg", ".ico", ".xbm", ".xpm"}
XMMS_TOP_DIRS = {
    "effect", "general", "input", "intl", "libxmms", "output", "po",
    "visualization", "wmxmms", "xmms", "vms",
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def is_link(path: Path) -> bool:
    return path.is_symlink() or bool(getattr(path, "is_junction", lambda: False)())


def omit_reason(path: Path, directory: bool = False) -> str | None:
    name = path.name.casefold()
    if name in OMIT_DIRS or (directory and name.startswith(".")):
        return "private or generated directory"
    if not directory and name.startswith(".") and name not in {".gitattributes", ".gitignore"}:
        return "private hidden file"
    if PRIVATE_NAME.search(name) or name == ".env" or name.startswith(".env."):
        return "private filename"
    if not directory and name in MMOV_SDK_NAMES:
        return "external MMOV SDK header"
    if not directory and (path.suffix.casefold() in OMIT_SUFFIXES or name in OMIT_NAMES):
        return "binary, build output, log or archive"
    if not directory and (name.endswith(("~", ".pem", ".key")) or ";" in name):
        return "backup, key or prior file version"
    return None


def collect(label: str, root: Path, skipped: Counter) -> list[tuple[str, Path]]:
    result = []
    for current, directories, files in os.walk(root, followlinks=False):
        directory = Path(current)
        keep = []
        for name in sorted(directories):
            path = directory / name
            reason = omit_reason(path, True)
            if reason:
                skipped[reason] += 1
                continue
            if is_link(path):
                raise ValueError(f"Refusing linked source directory: {path}")
            if label == "xmms" and directory == root and name.casefold() not in XMMS_TOP_DIRS:
                raise ValueError(f"Unexpected XMMS top-level directory: {path}")
            keep.append(name)
        directories[:] = keep
        for name in sorted(files):
            path = directory / name
            reason = omit_reason(path)
            if reason:
                skipped[reason] += 1
                continue
            if is_link(path) or not stat.S_ISREG(path.stat().st_mode):
                raise ValueError(f"Refusing non-regular source file: {path}")
            resolved = path.resolve(strict=True)
            if not resolved.is_relative_to(root):
                raise ValueError(f"Source escapes its explicit root: {path}")
            relative = path.relative_to(root).as_posix()
            result.append((f"{label}/{relative}", path))
    return result


def zip_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    return info


def package(roots: dict[str, Path], output: Path) -> dict:
    roots = {name: path.resolve(strict=True) for name, path in roots.items()}
    for name, root in roots.items():
        if not root.is_dir():
            raise ValueError(f"{name} source root is not a directory")
        for other_name, other in roots.items():
            if name != other_name and root.is_relative_to(other):
                raise ValueError("Source roots must be distinct and non-overlapping")
    if output.exists() or output.is_symlink():
        raise ValueError("Output already exists; a new filename is required")
    output = output.resolve(strict=False)
    if output.suffix.casefold() != ".zip" or not output.parent.is_dir():
        raise ValueError("Output must be a .zip in an existing directory")
    if output.exists() or output.is_symlink():
        raise ValueError("Output already exists; a new filename is required")
    if any(output.is_relative_to(root) for root in roots.values()):
        raise ValueError("Output must be outside all input source roots")
    required = {
        "xmms": ["COPYING", "xmms/main.c", "Output/mmov/mmov.c", "vms/BUILD.COM"],
        "gtk": ["glib/glib.h", "glib/copying", "gtk/gtk/gtk.h", "gtk/copying"],
        "opl": ["vms_jackets.h", "license.txt", "gnu_public_license.txt"],
    }
    for label, names in required.items():
        for name in names:
            if not (roots[label] / name).is_file():
                raise ValueError(f"Required {label} source or notice missing: {name}")
    skipped: Counter = Counter()
    sources = sorted(item for label, root in roots.items() for item in collect(label, root, skipped))
    folded = [name.casefold() for name, _ in sources]
    if len(set(folded)) != len(folded):
        raise ValueError("Case-insensitive source pathname collision")
    entries = []
    created = False
    try:
        with output.open("xb") as stream:
            created = True
            with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
                for name, source in sources:
                    data = source.read_bytes()
                    if b"\0" in data and source.suffix.casefold() not in BINARY_SOURCE_ASSETS:
                        raise ValueError(f"Binary or unnormalized RMS text in source tree: {source}")
                    entries.append({"path": name, "bytes": len(data), "sha256": digest(data)})
                    archive.writestr(zip_info(name), data, compresslevel=9)
                manifest = {
                    "format": "openvms-xmms-corresponding-source-v1",
                    "roots": ["xmms", "gtk", "opl"],
                    "files": entries,
                }
                encoded = (json.dumps(manifest, sort_keys=True, indent=2) + "\n").encode("utf-8")
                archive.writestr(zip_info(MANIFEST), encoded, compresslevel=9)
            stream.flush()
            os.fsync(stream.fileno())
        # Read every ZIP member back and compare exact bytes/hash/size, not just CRC.
        with zipfile.ZipFile(output) as archive:
            expected = {item["path"] for item in entries} | {MANIFEST}
            names = archive.namelist()
            if len(names) != len(expected) or set(names) != expected:
                raise ValueError("ZIP inventory mismatch")
            if archive.read(MANIFEST) != encoded:
                raise ValueError("ZIP manifest roundtrip mismatch")
            for entry in entries:
                data = archive.read(entry["path"])
                if len(data) != entry["bytes"] or digest(data) != entry["sha256"]:
                    raise ValueError(f"ZIP roundtrip mismatch: {entry['path']}")
        # Reject source edits during packaging, including additions/removals.
        current = sorted(item for label, root in roots.items() for item in collect(label, root, Counter()))
        if [name for name, _ in current] != [name for name, _ in sources]:
            raise ValueError("Source inventory changed during packaging")
        for entry, (_, source) in zip(entries, sources):
            if digest(source.read_bytes()) != entry["sha256"]:
                raise ValueError(f"Source changed during packaging: {source}")
        return {
            "output": str(output), "bytes": output.stat().st_size,
            "sha256": digest(output.read_bytes()), "source_files": len(entries),
            "roundtrip_verified": True, "sources_unchanged": True,
            "excluded_counts": dict(sorted(skipped.items())),
        }
    except BaseException:
        if created:
            output.unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xmms-root", type=Path, required=True)
    parser.add_argument("--gtk-root", type=Path, required=True)
    parser.add_argument("--opl-root", type=Path, required=True,
                        help="OPL source normalized to text, not raw RMS record bytes")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = package({"xmms": args.xmms_root, "gtk": args.gtk_root, "opl": args.opl_root}, args.output)
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        print(f"Source package failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
