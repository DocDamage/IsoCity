"""Open mixed connection fixtures independently from the Studio checkout."""
import json
import os
from pathlib import Path
import shutil
import sys
import uuid
import zipfile

from verify_collection_portable import stage
from verify_companion_portable import settings
from verify_model_previews import port
from verify_school_portable import sha

ROOT = Path(__file__).resolve().parents[1]


def inspect(package, target, mode):
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
        assert not any(name.startswith((".godot/", "output/")) for name in names)
        assert "scripts/builder/edit_overlay.gd" not in names
        assert "scripts/builder/utility_tools.gd" not in names
        assert "scripts/builder/connector_tools.gd" not in names
        manifest = json.loads(archive.read("export-manifest.json"))
        for entry in manifest["files"]:
            contents = archive.read(entry["path"])
            assert len(contents) == entry["bytes"] and sha(contents) == entry["sha256"], entry["path"]
        source = json.loads(archive.read("city-source.json"))["documents"][mode]
        assert len(source["connections"]) == 1 and source["connections"][0]["uid"] == "verified_joint"
        assert sum(edge["kind"] == "water" for edge in source["utility_edges"]) == 2
        assert sum(edge["kind"] == "power" for edge in source["utility_edges"]) == 6
        assert not ({"stock", "reviewed", "socket_markers", "markers_visible"} & source.keys())
        archive.extractall(target)
        return len(manifest["files"])


def main():
    packages = Path(sys.argv[1]).resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    destination = ROOT.parent / "IsoCity-portable-validation" / "U11" / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        package = packages / f"connections_{mode}.zip"
        digest = sha(package.read_bytes())
        target = destination / mode
        target.mkdir(parents=True)
        files = inspect(package, target, mode)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_connection_export.gd", target / "verify_connections.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        for label, flags in (
            ("import", ["--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "1200", "--script", "res://verify_connections.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE CONNECTIONS: 5 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            results.append({"mode": mode, "package": str(package), "package_sha256": digest,
                            "stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes()),
                            "manifest_files_verified": files})
            print(f"PASS: connections {mode} {label}", flush=True)
        (packages / "portable_projects.json").write_text(
            json.dumps({"destination": str(destination), "results": results}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
