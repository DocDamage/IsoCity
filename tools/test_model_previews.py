"""Focused I05 regression tests; no user projects or GPU required."""
from pathlib import Path
import json
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image, ImageDraw
import model_previews as previews


def silhouette():
    image = Image.new("RGBA", (64, 64))
    ImageDraw.Draw(image).polygon([(32, 8), (55, 53), (32, 44), (9, 53)], fill="white")
    return image


class ModelPreviewsTest(unittest.TestCase):
    def root_fixture(self, root):
        for name in ("tools", "scripts", "assets/editor", "assets/supplemental_models"):
            (root / name).mkdir(parents=True, exist_ok=True)
        for name in ("tools/render_builder_previews.gd", "scripts/model_bounds.gd", "tools/model_previews.py"):
            (root / name).write_text("helper")
        silhouette().save(root / "assets/editor/missing_object.png")
        (root / "scene.tscn").write_text("model scene")
        (root / "model.tscn").write_text("prepared model")
        return {"ship": {"path": "res://scene.tscn", "data": {"model_file": "res://model.tscn",
                    "preview_path": "res://assets/supplemental_models/ship.png", "source_files": []}}}

    def test_missing_sources_use_visible_marker_and_retry(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); assets = self.root_fixture(root)
            self.assertEqual({"ship": "missing"}, previews.build_previews(assets, render=False, root=root))
            destination = root / "assets/supplemental_models/ship.png"
            self.assertEqual(previews.sha256(root / "assets/editor/missing_object.png"), previews.sha256(destination))
            self.assertEqual({"ship": "missing"}, previews.build_previews(assets, render=False, root=root))

    def test_fallback_pipeline_and_corrupt_manifest_recovery(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); assets = self.root_fixture(root)
            source = root / "assets/supplemental_source/3D_spaceships_pack_2/previews/ship.gif"
            source.parent.mkdir(parents=True)
            silhouette().save(source)
            assets["ship"]["data"]["source_files"] = ["res://assets/supplemental_source/3D_spaceships_pack_2_low/models/ship_low.glb"]
            (root / "assets/supplemental_models/preview_manifest.json").write_text("[]")
            self.assertEqual({"ship": "gif"}, previews.build_previews(assets, render=False, root=root))
            destination = root / "assets/supplemental_models/ship.png"
            before = destination.stat().st_mtime_ns
            self.assertEqual({"ship": "cached"}, previews.build_previews(assets, render=False, root=root))
            self.assertEqual(before, destination.stat().st_mtime_ns)
            silhouette().transpose(Image.Transpose.ROTATE_180).save(source)
            self.assertEqual({"ship": "gif"}, previews.build_previews(assets, render=False, root=root))

    def test_uniform_placeholder_and_transparent_noise_rejected(self):
        self.assertFalse(previews.meaningful(Image.new("RGBA", (128, 128), (38, 73, 93, 255))))
        self.assertFalse(previews.meaningful(Image.new("RGBA", (128, 128), (255, 0, 0, 0))))
        image = Image.new("RGBA", (128, 128), (38, 73, 93, 255))
        image.putpixel((0, 0), (255, 0, 0, 255))
        self.assertFalse(previews.meaningful(image))

    def test_monochrome_silhouette_is_valid(self):
        self.assertTrue(previews.meaningful(silhouette()))

    def test_atomic_write_and_idempotence(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "preview.png"
            previews.atomic_image(silhouette(), target)
            before = target.stat().st_mtime_ns
            previews.atomic_image(silhouette(), target)
            self.assertTrue(previews.valid_file(target))
            self.assertEqual(before, target.stat().st_mtime_ns)

    def test_invalid_image_does_not_replace_good_preview(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "preview.png"
            previews.atomic_image(silhouette(), target)
            before = target.read_bytes()
            with self.assertRaises(ValueError):
                previews.atomic_image(Image.new("RGBA", (64, 64)), target)
            self.assertEqual(before, target.read_bytes())

    def test_failed_write_does_not_replace_good_preview(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "preview.png"
            previews.atomic_image(silhouette(), target)
            before = target.read_bytes()
            with patch("model_previews.os.replace", side_effect=PermissionError("locked")):
                with self.assertRaises(PermissionError):
                    previews.atomic_image(silhouette().resize((192, 192)), target)
            self.assertEqual(before, target.read_bytes())
            self.assertEqual([target], list(Path(folder).iterdir()))

    def test_blank_first_gif_frame(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "ship.gif"
            Image.new("RGB", (64, 64), "black").save(target, save_all=True,
                append_images=[silhouette().convert("RGB")], duration=100, loop=0)
            image = previews.gif_frame(target)
            self.assertIsNotNone(image)
            self.assertEqual((192, 192), image.size)
            self.assertTrue(previews.meaningful(image))

    def test_missing_and_flat_gifs(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "missing.gif"
            self.assertIsNone(previews.gif_frame(target))
            Image.new("RGB", (64, 64), "black").save(target)
            self.assertIsNone(previews.gif_frame(target))

    def test_full_detail_lookup_and_sorted_candidates(self):
        with tempfile.TemporaryDirectory() as folder:
            raw = Path(folder)
            low = raw / "3D_spaceships_pack_2_low/models/ship_low.glb"
            low.parent.mkdir(parents=True)
            low.touch()
            full = raw / "3D_spaceships_pack_2/previews"
            full.mkdir(parents=True)
            for name in ("z", "a"):
                (full / name).mkdir()
                silhouette().save(full / name / "ship.gif")
            (full / "unrelated.gif").touch()
            found = previews.gif_candidates([str(low)], raw)
            self.assertEqual([full / "a/ship.gif", full / "z/ship.gif"], found)

    def test_cache_retries_fallback_when_renderer_becomes_available(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "preview.png"
            previews.atomic_image(silhouette(), target)
            entry = {"key": "key", "sha256": previews.sha256(target), "method": "gif"}
            self.assertTrue(previews.cache_hit(entry, "key", target, False))
            self.assertFalse(previews.cache_hit(entry, "key", target, True))
            entry["method"] = "render"
            self.assertTrue(previews.cache_hit(entry, "key", target, True))
            self.assertFalse(previews.cache_hit(entry, "changed", target, True))
            target.write_bytes(b"corrupt")
            self.assertFalse(previews.cache_hit(entry, "key", target, True))

    def test_dependency_hash_tracks_material_geometry_and_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ("tools", "scripts"):
                (root / name).mkdir()
            for name in ("tools/render_builder_previews.gd", "scripts/model_bounds.gd", "tools/model_previews.py"):
                (root / name).write_text("helper")
            # A GLB with external texture; exercise the real dependency walker.
            import struct
            data = json.dumps({"images": [{"uri": "material.png"}]}).encode()
            (root / "model.glb").write_bytes(struct.pack("<IIIII", 0x46546c67, 2, 20 + len(data), len(data), 0x4E4F534A) + data)
            (root / "material.png").write_bytes(b"material")
            scene = root / "scene.tscn"
            scene.write_text('path="res://model.glb"')
            asset = {"path": "res://scene.tscn", "data": {"model_file": "res://model.glb"}}
            before = previews.dependency_hash(asset, root)
            self.assertEqual(before, previews.dependency_hash(asset, root))
            (root / "material.png").write_bytes(b"new material")
            self.assertNotEqual(before, previews.dependency_hash(asset, root))
            before = previews.dependency_hash(asset, root)
            scene.write_text(scene.read_text() + "\nscale = 2")
            self.assertNotEqual(before, previews.dependency_hash(asset, root))
            before = previews.dependency_hash(asset, root)
            with patch.dict(previews.SETTINGS, {"version": 999}):
                self.assertNotEqual(before, previews.dependency_hash(asset, root))
            before = previews.dependency_hash(asset, root)
            (root / 'model.glb.import').write_text('nodes/root_scale=2')
            self.assertNotEqual(before, previews.dependency_hash(asset, root))


if __name__ == "__main__":
    unittest.main()
