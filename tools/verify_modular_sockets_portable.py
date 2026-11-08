"""Verify linked city and assembly packages in fresh projects on F:."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import uuid
import zipfile

from verify_collection_portable import stage
from verify_companion_portable import settings
from verify_model_previews import port

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_document(archive, mode):
    return json.loads(archive.read("city-source.json"))["documents"][mode]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("packages", type=Path)
    args = parser.parse_args()
    package_dir = args.packages.resolve()
    engine = os.environ["GODOT_BIN"]
    destination = Path(r"F:\dev\IsoCity-portable-validation\I08") / uuid.uuid4().hex
    results = []
    for stem, mode in (
        ("socket_2d", "2d"), ("socket_scaffold_module", "3d"), ("socket_fence_panel", "3d"),
        ("pipe_internal_pending", "2d"), ("pipe_internal_built", "2d"),
        ("pipe_external_pending", "2d"), ("pipe_external_built", "2d"),
    ):
        package = package_dir / (stem + ".zip")
        target = destination / stem
        target.mkdir(parents=True)
        package_hash = sha(package.read_bytes())
        expected_zip = package_dir / (stem.replace("_pending", "_built") + ".zip")
        with zipfile.ZipFile(expected_zip) as completed:
            expected = read_document(completed, mode)
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
            assert not any(".godot/" in name or name.startswith("output/") for name in names)
            for entry in json.loads(archive.read("export-manifest.json"))["files"]:
                data = archive.read(entry["path"])
                assert len(data) == entry["bytes"] and sha(data) == entry["sha256"], entry["path"]
            for path in ("resources/catalog/connectors.json", "scripts/builder/connector_plan.gd",
                         "scripts/builder/functional_assembly_plan.gd"):
                assert sha(archive.read(path)) == sha((ROOT / path).read_bytes()), path
            source = read_document(archive, mode)
            assert bool(source.get("blueprints")) == stem.endswith("_pending")
            assert expected["connections"]
            archive.extractall(target)
        assert not (target / ".godot").exists()
        (target / "expected_sockets.json").write_text(json.dumps(expected), encoding="utf-8")
        shutil.copyfile(ROOT / "tools/test_modular_sockets_export.gd", target / "verify_sockets.gd")
        project = target / "project.godot"
        original = settings(project.read_bytes())
        for label, flags in (
            ("import", ["--headless", "--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--script", "res://verify_sockets.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            stage([engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags], target, label, 180)
            assert settings(project.read_bytes()) == original and sha(package.read_bytes()) == package_hash
            log = target / f"verification_{label}.log"
            results.append({"package": str(package), "stage": label, "log": str(log),
                            "sha256": sha(log.read_bytes()), "package_sha256": package_hash})
            print(f"PASS: {stem} {label}", flush=True)
        (package_dir / "portable_projects.json").write_text(
            json.dumps({"destination": str(destination), "results": results}, indent=2) + "\n",
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
