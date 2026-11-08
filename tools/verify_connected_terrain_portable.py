"""Import and run a connected terrain project independently on the checkout drive."""
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


def main():
    out = Path(sys.argv[1]).resolve()
    package = out / "connected_terrain.zip"
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    target = ROOT.parent / "IsoCity-portable-validation" / "I09" / uuid.uuid4().hex
    target.mkdir(parents=True)
    digest = sha(package.read_bytes())
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
        assert not any(name.startswith((".godot/", "output/")) for name in names)
        manifest = json.loads(archive.read("export-manifest.json"))
        for entry in manifest["files"]:
            content = archive.read(entry["path"])
            assert len(content) == entry["bytes"] and sha(content) == entry["sha256"], entry["path"]
        for name in ("resources/catalog/terrain_families.json",
                     "assets/pixel_isometric/Tilesets/City_Ground_Iso_Tileset_32x16.png",
                     "assets/pixel_isometric/Tilesets/Animated_Tiles_32x16.png"):
            assert archive.read(name) == (ROOT / name).read_bytes()
        data = json.loads(archive.read("city-source.json"))["documents"]["2d"]
        assert {tile["family"] for tile in data["tiles"] if "family" in tile} == {"shore", "path"}
        assert not ({"family_cache", "family_variants", "terrain_markers"} & data.keys())
        archive.extractall(target)
    assert not (target / ".godot").exists()
    shutil.copyfile(ROOT / "tools/test_connected_terrain_export.gd", target / "verify_connected_terrain.gd")
    project = target / "project.godot"
    initial = settings(project.read_bytes())
    results = []
    for label, flags in (
        ("import", ["--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
        ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "1200", "--script", "res://verify_connected_terrain.gd"]),
        ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
    ):
        command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
        stage(command, target, label, 180)
        log = target / f"verification_{label}.log"
        if label == "runtime":
            assert "PORTABLE CONNECTED TERRAIN: 4 checks, 0 failures" in log.read_text(encoding="utf-8")
        assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
        results.append({"stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
        print(f"PASS: connected terrain {label}", flush=True)
    (out / "portable_project.json").write_text(json.dumps({"destination": str(target), "package_sha256": digest,
        "manifest_files_verified": len(manifest["files"]), "results": results}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
