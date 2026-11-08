"""Verify the authored companions in independent portable projects on F:."""
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
FILES = (
    "resources/catalog/pets.json",
    "scripts/builder/pet_actor.gd",
    "scripts/builder/pet_commands.gd",
    "scripts/builder/pet_navigation.gd",
    "scripts/builder/pet_plan.gd",
    "scripts/builder/pet_runtime.gd",
    "scripts/builder/walk_obstacles.gd",
    "scenes/items/Pets/Dog_Golden.tscn",
)


def main():
    out = Path(sys.argv[1]).resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    destination = ROOT.parent / "IsoCity-portable-validation" / "N13" / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        target = destination / mode
        target.mkdir(parents=True)
        package = out / f"pet_{mode}.zip"
        digest = sha(package.read_bytes())
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
            assert not any(name.startswith((".godot/", "output/")) for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                content = archive.read(entry["path"])
                assert len(content) == entry["bytes"] and sha(content) == entry["sha256"], entry["path"]
            directions = [f"assets/pixel_isometric/Sprites/Pets/Dog_Golden_{direction}.png" for direction in ("SE", "SW", "NW", "NE")]
            for name in (*FILES, *directions):
                assert archive.read(name) == (ROOT / name).read_bytes(), name
            source = json.loads(archive.read("city-source.json"))["documents"][mode]
            assert source["pet"]["enabled"] and source["pet"]["asset"] == "2d:Dog_Golden"
            assert not any(item["asset"] == "2d:Dog_Golden" for item in source["objects"])
            assert not {"companion_owner", "pet_actor", "pet_path"}.intersection(source)
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_pet_export.gd", target / "verify_pet.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        runs = []
        for label, flags in (
            ("import", ["--headless", "--editor", "--import", "--accessibility-driver", "dummy",
                        "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "2400",
                         "--script", "res://verify_pet.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE PET: 7 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            runs.append({"stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
            print(f"PASS: pet {mode} {label}", flush=True)
        results.append({"mode": mode, "destination": str(target), "package_sha256": digest,
                        "manifest_files_verified": len(manifest["files"]), "results": runs})
    (out / "portable_projects.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
