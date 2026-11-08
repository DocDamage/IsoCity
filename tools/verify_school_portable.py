"""Run school life in freshly relocated Godot source exports."""
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("packages", type=Path)
    args = parser.parse_args()
    packages = args.packages.resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    destination = ROOT.parent / "IsoCity-portable-validation" / "N01" / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        package = packages / f"school_{mode}.zip"
        target = destination / mode
        target.mkdir(parents=True)
        digest = sha(package.read_bytes())
        with zipfile.ZipFile(package) as archive:
            names = set(archive.namelist())
            assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
            assert not any(".godot/" in name or name.startswith("output/") for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                data = archive.read(entry["path"])
                assert len(data) == entry["bytes"] and sha(data) == entry["sha256"], entry["path"]
            for name in (
                "scripts/builder/school_plan.gd", "scripts/builder/school_runtime.gd",
                "resources/catalog/schools.json", "scripts/builder/transit_runtime.gd",
                "scripts/builder/transit_passengers.gd",
                "scripts/builder/citizen_runtime.gd", "scripts/builder/resident_activities.gd",
                "resources/previews_3d/HanX_School/School_Building.png",
                "resources/previews_3d/HanX_School/Student_Chair.png",
            ):
                assert sha(archive.read(name)) == sha((ROOT / name).read_bytes()), name
            native_bus = "2d:School_Bus" if mode == "2d" else "3d:HanX_School/School_Bus"
            assert native_bus in manifest["assets"]
            school_preview = ("assets/pixel_isometric/Sprites/Vehicles/School_Bus_SE.png" if mode == "2d"
                              else "resources/previews_3d/HanX_School/School_Bus.png")
            assert sha(archive.read(school_preview)) == sha((ROOT / school_preview).read_bytes())
            source = json.loads(archive.read("city-source.json"))["documents"][mode]
            schools = [item["school"] for item in source["objects"] if "school" in item]
            assert len(schools) == 1 and schools[0]["bus_line"] == "school_line"
            assert source["transit_lines"][0]["school_bus"] is True
            assert not any(key in schools[0] for key in ("attendance", "trips", "enrolled"))
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_school_export.gd", target / "verify_school.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        for label, flags in (
            ("import", ["--headless", "--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "120000", "--script", "res://verify_school.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            stage([engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags], target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE SCHOOL: 6 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            results.append({"mode": mode, "package": str(package), "stage": label, "log": str(log),
                            "sha256": sha(log.read_bytes()), "package_sha256": digest})
            print(f"PASS: {mode} {label}", flush=True)
        (packages / "portable_projects.json").write_text(
            json.dumps({"destination": str(destination), "results": results}, indent=2) + "\n", encoding="utf-8"
        )


if __name__ == "__main__":
    main()
