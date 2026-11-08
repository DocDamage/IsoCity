"""Rebuildable model thumbnails: rendered prepared scenes, then supplied GIFs.

No catalog IDs or model geometry are changed. Manifests are derived caches and
are deliberately separate from the portable runtime registry.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import tempfile
from urllib.parse import unquote
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = {"version": 1, "size": 192, "margin": 16,
            "renderer": "gl_compatibility", "view": [1, .85, 1]}
ALTERNATIVES = {"3D_arcade_machines_pack_lowpoly": "3D_arcade_machines_pack",
                "3D_satellites_pack_low": "3D_satellites_pack",
                "3D_spaceships_pack_2_low": "3D_spaceships_pack_2"}


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def local(path, root=ROOT):
    return root / path.removeprefix("res://")


def meaningful(image):
    """Reject blank/flat model placeholders, accepting monochrome silhouettes.

    This policy applies only to generated model previews, never sprite tiles.
    Transparent RGB is ignored so invisible noise cannot pass the check.
    """
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    bounds = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
    if not bounds:
        return False
    visible = sum(alpha.histogram()[9:])
    if visible < 16:
        return False
    # A cut-out silhouette is meaningful even if every visible pixel is white.
    if visible < rgba.width * rgba.height * .98:
        return True
    rgb = Image.new("RGB", rgba.size, (38, 73, 93))
    rgb.paste(rgba, mask=alpha)
    small = rgb.resize((64, 64), Image.Resampling.BOX)
    extrema = small.getextrema()
    if max(high - low for low, high in extrema) < 8:
        return False
    # Reject a flat placeholder with only a few noisy pixels.
    colors = small.quantize(colors=16).getcolors()
    return max(count for count, _ in colors) < small.width * small.height * .995


def valid_file(path):
    try:
        with Image.open(path) as image:
            return meaningful(image)
    except (OSError, ValueError):
        return False


def atomic_image(image, destination):
    """Validate before replace; failure leaves an existing good file intact."""
    if not meaningful(image):
        raise ValueError("Empty or uniform model preview")
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".png", prefix=".preview-", dir=destination.parent, delete=False) as stream:
            temporary = Path(stream.name)
        image.convert("RGBA").save(temporary)
        if not valid_file(temporary):
            raise ValueError("Saved preview failed validation")
        if destination.exists() and temporary.read_bytes() == destination.read_bytes():
            return
        os.replace(temporary, destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def normalized(stem):
    return re.sub(r"(?:_lowpoly|_low)$", "", stem.casefold())


def gif_candidates(source_files, raw=None, root=ROOT):
    raw = Path(raw) if raw is not None else ROOT / "assets/supplemental_source"
    folders, keys = set(), set()
    for source in source_files:
        source = local(source, root)
        keys.add(normalized(source.stem))
        try:
            pack = source.relative_to(raw).parts[0]
        except (ValueError, IndexError):
            continue
        folders.add(raw / pack)
        if pack in ALTERNATIVES:
            folders.add(raw / ALTERNATIVES[pack])
    return sorted({path for folder in folders if folder.exists() for path in folder.rglob("*")
                   if path.suffix.casefold() == ".gif" and normalized(path.stem) in keys},
                  key=lambda path: path.as_posix().casefold())


def gif_frame(path):
    """Try up to 32 evenly spaced frames, including blank-first-frame GIFs."""
    try:
        with Image.open(path) as gif:
            count = getattr(gif, "n_frames", 1)
            indices = sorted({round(index * (count - 1) / max(1, min(count, 32) - 1))
                              for index in range(min(count, 32))})
            for index in indices:
                gif.seek(index)
                frame = gif.convert("RGBA")
                if not meaningful(frame):
                    continue
                frame.thumbnail((176, 176), Image.Resampling.LANCZOS)
                canvas = Image.new("RGBA", (192, 192))
                canvas.paste(frame, ((192 - frame.width) // 2, (192 - frame.height) // 2))
                return canvas
    except (OSError, ValueError, EOFError):
        pass
    return None


def dependency_files(asset, root=ROOT):
    pending = [local(asset["path"], root)]
    pending += [local(asset["data"]["model_file"], root)]
    pending += [root / "tools/render_builder_previews.gd", root / "scripts/model_bounds.gd", root / "tools/model_previews.py"]
    files = {}
    while pending:
        path = pending.pop().resolve()
        name = path.relative_to(root.resolve()).as_posix()
        if name in files:
            continue
        files[name] = sha256(path) if path.is_file() else "missing"
        if path.suffix.casefold() in ('.glb', '.gltf', '.png', '.jpg', '.jpeg', '.webp', '.tga', '.bmp', '.svg'):
            pending.append(path.with_name(path.name + '.import'))
        if path.is_file() and path.suffix in (".tscn", ".tres", ".gd", ".gdshader", ".gdshaderinc", ".import"):
            pending += [local(value, root) for value in re.findall(r'["\'](res://[^"\'\r\n]+)["\']', path.read_text(encoding="utf-8")) if not value.startswith('res://.godot/')]
        elif path.is_file() and path.suffix.casefold() in (".glb", ".gltf"):
            # Most supplied GLBs embed everything; hash external buffers/images too.
            import struct
            gltf = {}
            if path.suffix.casefold() == '.gltf': gltf = json.loads(path.read_text(encoding='utf-8'))
            else:
                with path.open("rb") as stream:
                    stream.seek(12)
                    length, kind = struct.unpack("<II", stream.read(8))
                    if kind == 0x4E4F534A: gltf = json.loads(stream.read(length))
            pending += [path.parent / unquote(entry["uri"]) for kind in ("buffers", "images")
                        for entry in gltf.get(kind, []) if "uri" in entry and not entry["uri"].startswith("data:")]
    return files


def dependency_hash(asset, root=ROOT):
    return hashlib.sha256(json.dumps({"files": dependency_files(asset, root), "settings": SETTINGS}, sort_keys=True).encode()).hexdigest()


def stage_models(assets, root, destination):
    """Import only selected prepared dependencies, leaving the source cache alone."""
    for asset in assets:
        for name, signature in dependency_files(asset, root).items():
            if signature == 'missing': continue
            source = root / name
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists(): shutil.copyfile(source, target)
    (destination / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="IsoCity model preview build"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')


def cache_hit(entry, key, destination, renderer_available):
    return (entry.get("key") == key and valid_file(destination)
            and entry.get("sha256") == sha256(destination)
            and (entry.get("method") == "render" or not renderer_available))


def preview_key(asset, candidates, engine, root):
    return hashlib.sha256(json.dumps({'prepared': dependency_hash(asset, root), 'engine': engine,
        'fallbacks': {str(path.relative_to(root)): sha256(path) for path in candidates}}, sort_keys=True).encode()).hexdigest()


def free_port():
    with socket.socket() as connection:
        connection.bind(('127.0.0.1', 0))
        return str(connection.getsockname()[1])


def build_previews(assets, *, godot=None, render=True, force=False, root=ROOT):
    executable = godot or os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    executable = executable if render else None
    report = root / "output/verification/asset_expansion/I05"
    report.mkdir(parents=True, exist_ok=True)
    manifest_path = root / "assets/supplemental_models/preview_manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        manifest = {"version": 1, "assets": {}}
    if not isinstance(manifest, dict) or manifest.get("version") != 1 or not isinstance(manifest.get("assets"), dict):
        manifest = {"version": 1, "assets": {}}
    cache = manifest.setdefault("assets", {})
    engine = "unavailable"
    if executable:
        try:
            version = subprocess.run([str(executable), "--version"], capture_output=True, text=True, timeout=15)
            engine = version.stdout.strip() if version.returncode == 0 else "unavailable"
            if version.returncode: executable = None
        except (OSError, subprocess.TimeoutExpired):
            executable = None
    pending, results = [], {}
    for ident, asset in sorted(assets.items()):
        destination = local(asset["data"]["preview_path"], root)
        candidates = gif_candidates(asset["data"].get("source_files", []), root / "assets/supplemental_source", root)
        entry = cache.get(ident, {})
        if not isinstance(entry, dict): entry = {}
        # A machine without rendering support may reuse a good rendered image.
        # A GIF cache is retried when rendering becomes available again.
        cached_engine = entry.get("engine", "unavailable") if entry.get("method") == "render" else "unavailable"
        engine_key = engine if executable else cached_engine
        key = preview_key(asset, candidates, engine_key, root)
        if not force and cache_hit(entry, key, destination, bool(executable)):
            results[ident] = "cached"
        else:
            pending.append((ident, asset, destination, candidates, key, engine_key))
    errors = []
    with tempfile.TemporaryDirectory(prefix="render-", dir=report) as temporary:
        temporary = Path(temporary)
        jobs = [{"scene": asset["path"], "output": str(temporary / f"{index}.png")}
                for index, (_, asset, _, _, _, _) in enumerate(pending)]
        if executable and jobs:
            staged = temporary / 'project'
            stage_models([asset for _, asset, _, _, _, _ in pending], root, staged)
            job_path = temporary / "jobs.json"
            job_path.write_text(json.dumps(jobs), encoding="utf-8")
            command = [str(executable), "--path", str(staged), "--rendering-method", SETTINGS["renderer"],
                       "--resolution", "192x192", "--position", "-10000,-10000",
                       "--script", "res://tools/render_builder_previews.gd", "--", "--jobs", str(job_path)]
            try:
                # Runtime loading alone can reuse a stale .godot model import.
                # Finish one import before rendering any changed prepared scene.
                imported = subprocess.run([str(executable), '--headless', '--path', str(staged), '--editor', '--import', '--quit',
                    '--lsp-port', free_port(), '--dap-port', free_port()], capture_output=True, text=True,
                    encoding='utf-8', errors='replace', timeout=180)
                (report / 'preview_import.log').write_text(f'Process exit: {imported.returncode}\n' + imported.stdout + imported.stderr, encoding='utf-8')
                if imported.returncode == 0:
                    rendered = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
                    (report / "render.log").write_text(rendered.stdout + rendered.stderr, encoding="utf-8")
                    if rendered.returncode: print("Renderer failed; checking supplied previews (see render.log)")
                else: print('Model import failed; checking supplied previews (see preview_import.log)')
            except (OSError, subprocess.TimeoutExpired) as error:
                (report / "render.log").write_text(str(error), encoding="utf-8")
        for index, (ident, asset, destination, candidates, key, engine_key) in enumerate(pending):
            image, method = None, "missing"
            rendered_path = Path(jobs[index]["output"])
            if valid_file(rendered_path):
                with Image.open(rendered_path) as rendered_image:
                    image = rendered_image.convert("RGBA")
                method = "render"
            else:
                for path in candidates:
                    image = gif_frame(path)
                    if image is not None:
                        method = "gif"
                        break
            try:
                if image is not None:
                    atomic_image(image, destination)
                    key = preview_key(asset, candidates, engine_key, root)
                    cache[ident] = {"key": key, "method": method, "sha256": sha256(destination), "engine": engine_key}
                elif not valid_file(destination) or sha256(destination) == sha256(root / "assets/editor/missing_object.png"):
                    # Keep the established path usable for portable collection, with
                    # the same explicit missing-art marker used by the library.
                    with Image.open(root / "assets/editor/missing_object.png") as missing:
                        atomic_image(missing, destination)
                    cache.pop(ident, None)  # Retry missing previews on the next run.
                else:
                    method = "retained"
            except (OSError, ValueError) as error:
                errors.append(f"{ident}: {error}")
                method = "write_failed"
            results[ident] = method
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    serialized = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    if not manifest_path.exists() or manifest_path.read_bytes() != serialized:
        temporary = manifest_path.with_suffix(".json.partial")
        temporary.write_bytes(serialized)
        os.replace(temporary, manifest_path)
    from collections import Counter
    print("Model previews:", dict(Counter(results.values())))
    (report / "preview_results.json").write_text(json.dumps({"results": results, "errors": errors}, indent=2) + "\n", encoding="utf-8")
    if errors:
        raise RuntimeError("Preview write failed: " + "; ".join(errors))
    return results
