"""Verify fresh, independent imports of the U20 Pixel and Model packages."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid
from zipfile import ZipFile

from verify_collection_portable import stage
from verify_model_previews import port
from verify_school_portable import sha

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/verification/asset_expansion/U20"


def run_import(engine, target, mode, windows_model_renderer="", wait_for_windows=False, headless_observer=False):
    command = [engine, "--path", str(target), "--log-file", str(target / "engine_import.log"),
               "--editor", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]
    if os.name != "nt" or (mode != "3d" and not wait_for_windows):
        command += ["--headless", "--import"]
        stage(command, target, "import", 180)
        return command
    # The Windows Forward+ editor can fault when --import exits during
    # teardown. Run the repository's observer until the imports settle.
    plugin = target / "addons/isocity_verify_import"
    plugin.mkdir(parents=True)
    shutil.copyfile(ROOT / "tools/portable_import_wait.gd", plugin / "plugin.gd")
    (plugin / "plugin.cfg").write_text(
        '[plugin]\nname="Verify imports"\nauthor="IsoCity"\nversion="1.0"\nscript="plugin.gd"\n',
        encoding="utf-8",
    )
    project = target / "project.godot"
    original = project.read_bytes()
    assert b"[editor_plugins]" not in original
    project.write_bytes(original + b'\n[editor_plugins]\nenabled=PackedStringArray("res://addons/isocity_verify_import/plugin.cfg")\n')
    command += ["--max-fps", "60"]
    if mode == "3d" and windows_model_renderer:
        command += ["--rendering-method", windows_model_renderer]
    if headless_observer:
        command.insert(1, "--headless")
    try:
        stage(command, target, "import", 180)
    finally:
        project.write_bytes(original)
        for name in ("plugin.gd", "plugin.gd.uid", "plugin.cfg"):
            (plugin / name).unlink(missing_ok=True)
        plugin.rmdir()
        if not any(plugin.parent.iterdir()):
            plugin.parent.rmdir()
    assert "Editor imports complete; filesystem stable for two seconds." in (target / "verification_import.log").read_text(encoding="utf-8")
    return command


def run_relocated_stage(command, *, cwd, headless_observer=False, **options):
    """Keep legacy verifier output while observing Windows editor imports."""
    target = Path(cwd).resolve()
    if os.name == "nt" and target != ROOT and "--editor" in command and "--import" in command:
        mode = "2d" if target.name == "2d" else "3d"
        actual = run_import(command[0], target, mode, windows_model_renderer="gl_compatibility",
                            wait_for_windows=True, headless_observer=headless_observer)
        log = (target / "verification_import.log").read_text(encoding="utf-8")
        return subprocess.CompletedProcess(actual, 0, stdout=log, stderr="")
    return subprocess.run(command, cwd=cwd, **options)


def main():
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable")
    destination = ROOT.parent / "IsoCity-portable-validation" / "U20" / uuid.uuid4().hex
    records = []
    for mode in ("2d", "3d"):
        target = destination / mode
        target.mkdir(parents=True)
        package = OUT / f"costs_{mode}.zip"
        package_hash = sha(package.read_bytes())
        with ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / name).resolve().is_relative_to(target) for name in names)
            assert not any(name.startswith((".godot/", "output/")) or "construction_cost_" in name for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                content = archive.read(entry["path"])
                assert len(content) == entry["bytes"] and sha(content) == entry["sha256"], entry["path"]
            if mode == "2d":
                assert any(name.endswith("/exterior-props/crate.png") for name in names)
            else:
                assert "assets/supplemental_models/Spaceships_II/LICENSE.txt" in names
                assert any(name.endswith("/hammerhead_cruiser_preview.png") for name in names)
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_construction_costs_export.gd", target / "verify_costs.gd")
        command = run_import(engine, target, mode)
        log = target / "verification_import.log"
        results = [{"stage": "import", "command": command, "log": str(log), "sha256": sha(log.read_bytes())}]
        print(f"PASS: construction costs {mode} import", flush=True)
        for label, flags in (
            ("runtime", ["--disable-vsync", "--audio-driver", "Dummy", "--quit-after",
                         "1200", "--script", "res://verify_costs.gd"]),
            ("visible_main", ["--disable-vsync", "--audio-driver", "Dummy", "--quit-after", "40"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE CONSTRUCTION COSTS: 5 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert sha(package.read_bytes()) == package_hash
            results.append({"stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
            print(f"PASS: construction costs {mode} {label}", flush=True)
        records.append({"mode": mode, "destination": str(target), "package_sha256": package_hash,
                        "manifest_files_verified": len(manifest["files"]), "results": results})
    (OUT / "portable_projects.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
