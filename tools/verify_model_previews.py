"""Verify I05 images, stable geometry and optional fresh portable runtimes."""
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import uuid
import zipfile
from PIL import Image, ImageDraw
import model_previews as previews

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/verification/asset_expansion/I05"


def port():
    with socket.socket() as connection:
        connection.bind(("127.0.0.1", 0))
        return str(connection.getsockname()[1])


def portable_target(output):
    """Keep generated imports on a roomy drive when the source drive is full."""
    override = os.environ.get("ISOCITY_VERIFY_ROOT")
    base = Path(override).expanduser().resolve() / output.name if override else output
    return base / "relocated" / uuid.uuid4().hex


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--portable", action="store_true", help="Import and run previously generated preview_2d/3d.zip packages")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    registry = json.loads((ROOT / "resources/catalog/supplemental_registry.json").read_text(encoding="utf-8"))
    fixture = json.loads((ROOT / "tools/fixtures/asset_expansion/model_previews.json").read_text(encoding="utf-8"))
    ids = fixture["assets"]
    assert len(ids) == 25 and sorted(ident for ident in registry["models"] if ident.startswith("3d:Supplemental_Spaceships_II/")) == ids
    sheet = Image.new("RGB", (1200, 1200), (237, 238, 240)); draw = ImageDraw.Draw(sheet)
    for index, ident in enumerate(ids):
        asset = registry["models"][ident]
        path = previews.local(asset["data"]["preview_path"])
        assert previews.valid_file(path), f"Blank/uniform thumbnail: {ident}"
        x, y = (index % 5) * 240, (index // 5) * 240
        with Image.open(path) as prepared:
            image = prepared.convert("RGBA"); image.thumbnail((116, 192)); sheet.paste(image, (x, y + 22), image)
        for candidate in previews.gif_candidates(asset["data"]["source_files"]):
            source = previews.gif_frame(candidate)
            if source is not None:
                source.thumbnail((116, 192)); sheet.paste(source, (x + 120, y + 22), source); break
        draw.text((x + 3, y + 3), ident.rsplit("/", 1)[1], fill="black")
        draw.text((x + 4, y + 212), "Prepared", fill="black"); draw.text((x + 122, y + 212), "Source GIF", fill="black")
    sheet.save(OUT / "contact_sheet.png")
    baseline = OUT / "baseline/sha256.json"
    if baseline.exists():
        for name, expected in json.loads(baseline.read_text()).items():
            if name.endswith((".glb", ".tscn")) or name == "resources/catalog/supplemental_registry.json":
                assert previews.sha256(ROOT / name) == expected, f"Unexpected geometry/registry change: {name}"
        print("PASS: baseline geometry, transforms and registry unchanged")
    print("PASS: all 25 model previews contain meaningful artwork; contact_sheet.png written")
    if args.portable:
        godot = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
        if not godot: raise RuntimeError("Godot required for fresh portable verification")
        target_root = portable_target(OUT)
        for mode in ("2d", "3d"):
            target = target_root / mode; target.mkdir(parents=True)
            with zipfile.ZipFile(OUT / f"preview_{mode}.zip") as archive:
                for name in archive.namelist():
                    if not (target / name).resolve().is_relative_to(target.resolve()): raise RuntimeError(f"Unsafe archive path: {name}")
                archive.extractall(target)
            assert not (target / ".godot").exists(), "Package includes an import cache"
            shutil.copyfile(ROOT / "tools/test_model_previews_portable.gd", target / "verify_preview.gd")
            for stage, arguments in (
                ("import", ["--editor", "--import", "--quit", "--lsp-port", port(), "--dap-port", port()]),
                ("runtime", ["--fixed-fps", "60", "--script", "res://verify_preview.gd"]),
                ("main", ["--quit-after", "10"]),
            ):
                completed = subprocess.run([godot, "--headless", "--path", str(target), *arguments], cwd=target,
                                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
                output = completed.stdout + completed.stderr
                (OUT / f"portable_{mode}_{stage}.log").write_text(f"Process exit: {completed.returncode}\n" + output, encoding="utf-8")
                if completed.returncode or re.search(r"(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:|WARNING: .*were leaked at exit)", output):
                    raise RuntimeError(f"Portable {mode} {stage} failed (exit {completed.returncode}): {output[-3000:]}")
                print(f"PASS: relocated {mode} {stage}", flush=True)
        print("Retained independent projects:", target_root)


if __name__ == "__main__":
    main()
