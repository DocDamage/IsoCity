"""Fresh I02 subset checks on the existing allowed supplemental fixture."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import uuid
import zipfile
from verify_model_previews import port, portable_target

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/verification/asset_expansion/I02"


def main():
    godot = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not godot: raise RuntimeError("Godot required")
    target_root = portable_target(OUT)
    for mode in ("2d", "3d"):
        target = target_root / mode; target.mkdir(parents=True)
        with zipfile.ZipFile(ROOT / "output" / f"supplemental_{mode}.zip") as archive:
            assert "resources/catalog/asset_metadata.json" in archive.namelist()
            for name in archive.namelist():
                if not (target / name).resolve().is_relative_to(target.resolve()): raise RuntimeError(f"Unsafe path: {name}")
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_asset_families_portable.gd", target / "verify_families.gd")
        for stage, arguments in (
            ("import", ["--editor", "--import", "--quit", "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--fixed-fps", "60", "--script", "res://verify_families.gd"]),
            ("main", ["--quit-after", "10"]),
        ):
            completed = subprocess.run([godot, "--headless", "--path", str(target), *arguments], cwd=target,
                                       capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
            output = completed.stdout + completed.stderr
            (OUT / f"portable_{mode}_{stage}.log").write_text(f"Process exit: {completed.returncode}\n" + output, encoding="utf-8")
            if completed.returncode or re.search(r"(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:|WARNING: .*were leaked at exit)", output):
                raise RuntimeError(f"I02 {mode} {stage}, exit {completed.returncode}: {output[-3000:]}")
            print(f"PASS: I02 relocated {mode} {stage}", flush=True)
    print("Retained independent projects:", target_root)


if __name__ == "__main__": main()
