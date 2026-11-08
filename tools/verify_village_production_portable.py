"""Open the native village packages independently from the builder checkout."""
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
    "resources/catalog/village_production.json",
    "scripts/builder/village_plan.gd",
    "scripts/builder/village_ledger.gd",
    "scripts/builder/village_runtime.gd",
    "scripts/builder/village_view.gd",
)


def main():
    out = Path(sys.argv[1]).resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    destination = ROOT.parent / "IsoCity-portable-validation" / "N17" / uuid.uuid4().hex
    results = []
    for variant in ("2d", "3d", "truck"):
        target = destination / variant
        target.mkdir(parents=True)
        package = out / f"village_{variant}.zip"
        digest = sha(package.read_bytes())
        truck = variant == "truck"
        mode = "3d" if truck else variant
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
            assert not any(name.startswith((".godot/", "output/")) for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                content = archive.read(entry["path"])
                assert len(content) == entry["bytes"] and sha(content) == entry["sha256"], entry["path"]
            dependencies = (*FILES, "scenes/items_3d/HanX_Shop/Cardboard_Boxes.tscn") if truck else FILES
            for name in dependencies:
                assert archive.read(name) == (ROOT / name).read_bytes(), name
            source = json.loads(archive.read("city-source.json"))["documents"][mode]
            assert source["village"]["enabled"]
            assert sum(item.get("village", {}).get("enabled", False) for item in source["objects"]) == (2 if truck else 6)
            assert not {"village_stock", "village_transfers", "village_wallet"}.intersection(source)
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_village_production_export.gd", target / "verify_village.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        runs = []
        for label, flags in (
            ("import", ["--headless", "--editor", "--import", "--accessibility-driver", "dummy",
                        "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "5100",
                         "--script", "res://verify_village.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                expected = 3 if truck else 7
                assert f"PORTABLE VILLAGE: {expected} checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            runs.append({"stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
            print(f"PASS: village {variant} {label}", flush=True)
        results.append({"variant": variant, "destination": str(target), "package_sha256": digest,
                        "manifest_files_verified": len(manifest["files"]), "results": runs})
    (out / "portable_projects.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
