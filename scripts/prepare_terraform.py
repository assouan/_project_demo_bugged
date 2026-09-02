#!/usr/bin/env python3
"""Installe une release Terraform epinglee dans le workspace Jenkins."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import ssl
import stat
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path


MAX_ARCHIVE_BYTES = 128 * 1024 * 1024
MAX_BINARY_BYTES = 256 * 1024 * 1024
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


class PreparationError(RuntimeError):
    pass


def load_manifest(path: Path) -> dict:
    raw = path.read_bytes()
    value = json.loads(raw)
    expected = {
        "schema_version",
        "version",
        "platform",
        "release_url",
        "archive_sha256",
        "binary_sha256",
        "runner_image",
    }
    version = value.get("version") if isinstance(value, dict) else None
    expected_url = (
        f"https://releases.hashicorp.com/terraform/{version}/"
        f"terraform_{version}_linux_amd64.zip"
    )
    if (
        len(raw) > 16_384
        or not isinstance(value, dict)
        or set(value) != expected
        or value.get("schema_version") != 1
        or not isinstance(version, str)
        or re.fullmatch(r"[0-9]+[.][0-9]+[.][0-9]+", version) is None
        or value.get("platform") != "linux_amd64"
        or value.get("release_url") != expected_url
        or SHA256_PATTERN.fullmatch(str(value.get("archive_sha256", ""))) is None
        or SHA256_PATTERN.fullmatch(str(value.get("binary_sha256", ""))) is None
        or re.fullmatch(
            r"[^\s@]+@sha256:[0-9a-f]{64}", str(value.get("runner_image", ""))
        )
        is None
    ):
        raise PreparationError("invalid manifest")
    return value


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def prepare(manifest_path: Path, output_directory: Path) -> dict:
    manifest = load_manifest(manifest_path)
    output_directory = output_directory.resolve()
    if output_directory.exists() and (
        output_directory.is_symlink() or not output_directory.is_dir()
    ):
        raise PreparationError("unsafe output directory")
    output_directory.mkdir(parents=True, exist_ok=True)
    archive_handle = tempfile.NamedTemporaryFile(
        prefix="terraform-release-", suffix=".zip", dir=output_directory, delete=False
    )
    archive_handle.close()
    archive_path = Path(archive_handle.name)
    binary_path = output_directory / "terraform"
    temporary_binary = output_directory / ".terraform.tmp"
    try:
        request = urllib.request.Request(
            manifest["release_url"], headers={"User-Agent": "alten-project-ci/1"}
        )
        size = 0
        with urllib.request.urlopen(
            request, context=ssl.create_default_context(), timeout=60
        ) as response, archive_path.open("wb") as output:
            if getattr(response, "status", 200) != 200:
                raise PreparationError("download failed")
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_ARCHIVE_BYTES:
                    raise PreparationError("archive too large")
                output.write(chunk)
        if size == 0 or digest_file(archive_path) != manifest["archive_sha256"]:
            raise PreparationError("archive checksum mismatch")
        with zipfile.ZipFile(archive_path) as archive:
            entries = archive.infolist()
            if [entry.filename for entry in entries] != ["LICENSE.txt", "terraform"]:
                raise PreparationError("unexpected archive inventory")
            binary_entry = entries[1]
            mode = (binary_entry.external_attr >> 16) & 0xFFFF
            if (
                binary_entry.is_dir()
                or stat.S_ISLNK(mode)
                or not 0 < binary_entry.file_size <= MAX_BINARY_BYTES
            ):
                raise PreparationError("unsafe binary entry")
            digest = hashlib.sha256()
            extracted_size = 0
            with archive.open(binary_entry) as source, temporary_binary.open("wb") as output:
                while chunk := source.read(1024 * 1024):
                    extracted_size += len(chunk)
                    if extracted_size > MAX_BINARY_BYTES:
                        raise PreparationError("binary too large")
                    digest.update(chunk)
                    output.write(chunk)
        if (
            extracted_size != binary_entry.file_size
            or digest.hexdigest() != manifest["binary_sha256"]
        ):
            raise PreparationError("binary checksum mismatch")
        os.chmod(temporary_binary, 0o500)
        os.replace(temporary_binary, binary_path)
        return {
            "archive_sha256": manifest["archive_sha256"],
            "binary_sha256": manifest["binary_sha256"],
            "status": "terraform-toolchain-ready",
            "version": manifest["version"],
        }
    finally:
        archive_path.unlink(missing_ok=True)
        temporary_binary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        proof = prepare(arguments.manifest.resolve(), arguments.output_directory)
    except Exception:
        print("terraform-toolchain-preparation-failed", file=sys.stderr)
        return 1
    print(json.dumps(proof, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
