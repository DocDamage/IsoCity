"""I01 overlay compiler regression checks using isolated catalog fixtures."""
from pathlib import Path
import json
import tempfile
import unittest
from compile_functional_defaults import compile_defaults


class FunctionalDefaultsTest(unittest.TestCase):
    def fixture(self, root):
        catalog = root / "resources/catalog"; catalog.mkdir(parents=True)
        scene = root / "scenes/items_3d/HanX_Shop/Shop_Cafe.tscn"; scene.parent.mkdir(parents=True); scene.touch()
        ident = "3d:HanX_Shop/Shop_Cafe"
        data = {"functional_defaults.json": {"version": 1, "revision": 1, "assets": {ident: {"business": "cafe", "citizen_role": "shop"}}},
                "businesses.json": {"existing-custom-id": "service"}, "citizen_roles.json": {"existing-custom-id": "work"},
                "asset_behaviors.json": {ident: {"building": True, "entrance": True, "entrance_anchor": {"point": [0, 0, 0], "arrival": [0, 0, 2]}}}}
        for name, value in data.items(): (catalog / name).write_text(json.dumps(value), encoding="utf-8")
        return catalog

    def test_idempotent_and_preserves_unrelated_defaults(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); catalog = self.fixture(root)
            with self.assertRaises(ValueError): compile_defaults(root, check=True)
            compile_defaults(root)
            before = {path: (path.stat().st_mtime_ns, path.read_bytes()) for path in catalog.glob("*.json")}
            compile_defaults(root); compile_defaults(root, check=True)
            self.assertEqual(before, {path: (path.stat().st_mtime_ns, path.read_bytes()) for path in before})
            self.assertEqual("service", json.loads((catalog / "businesses.json").read_text())["existing-custom-id"])

    def test_unknown_id_does_not_write_catalog(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); catalog = self.fixture(root)
            (root / "scenes/items_3d/HanX_Shop/Shop_Cafe.tscn").unlink()
            before = (catalog / "businesses.json").read_bytes()
            with self.assertRaises(ValueError): compile_defaults(root)
            self.assertEqual(before, (catalog / "businesses.json").read_bytes())

    def test_entrance_review_is_required(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); catalog = self.fixture(root)
            (catalog / "asset_behaviors.json").write_text("{}")
            with self.assertRaises(ValueError): compile_defaults(root)

    def test_reviewed_civic_sprite_requires_registry_scene_and_real_anchor(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); catalog = self.fixture(root)
            ident = "2d:city_Hall"
            (catalog / "catalog_registry.json").write_text(json.dumps({"items": {"city_Hall": {"category": "RPG_Buildings"}}}))
            scene = root / "scenes/items/RPG_World/Buildings/city_Hall.tscn"
            scene.parent.mkdir(parents=True); scene.touch()
            overlay = json.loads((catalog / "functional_defaults.json").read_text())
            overlay["assets"][ident] = {"business": "service", "citizen_role": "shop"}
            (catalog / "functional_defaults.json").write_text(json.dumps(overlay))
            behavior = json.loads((catalog / "asset_behaviors.json").read_text())
            behavior[ident] = {"building": True, "entrance": True, "entrance_anchor": {"views": {"SE": {"point": [1, 2], "arrival": [1, 3]}}}}
            (catalog / "asset_behaviors.json").write_text(json.dumps(behavior))
            compile_defaults(root)
            self.assertEqual("service", json.loads((catalog / "businesses.json").read_text())[ident])
            scene.unlink()
            with self.assertRaises(ValueError): compile_defaults(root, check=True)

    def test_invalid_anchors_never_write_defaults(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); catalog = self.fixture(root)
            before = (catalog / "businesses.json").read_bytes()
            for value in ([0, 0], [True, 0, 0], [float('nan'), 0, 0], [10001, 0, 0], 'not a point'):
                behavior = {"3d:HanX_Shop/Shop_Cafe": {"building": True, "entrance": True, "entrance_anchor": {"point": value, "arrival": [0, 0, 2]}}}
                (catalog / "asset_behaviors.json").write_text(json.dumps(behavior))
                with self.assertRaises(ValueError): compile_defaults(root)
                self.assertEqual(before, (catalog / "businesses.json").read_bytes())


if __name__ == "__main__": unittest.main()
