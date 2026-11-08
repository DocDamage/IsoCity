"""Metadata compiler rules do not rename IDs or invent animation clips."""
from pathlib import Path
import json
import tempfile
import unittest
from compile_asset_metadata import family_metadata, sprite_status, mesh_status, runtime_actions


class AssetMetadataTest(unittest.TestCase):
    def test_supplied_door_states_are_not_movement_or_facing_animation(self):
        value = sprite_status({'kind':'obj', 'frames':1, 'source_view_kind':'state', 'directions':{'Closed':{'frames':1},'Open':{'frames':1}}})
        self.assertEqual('static_sprite', value['animation_status'])
        self.assertIn('states', value['animation_note'])

    def test_reviewed_actions_and_honest_run_fallback(self):
        clip = {'directions': {'SE': {'frames': 1}}}
        actions = runtime_actions({'kind': 'char', 'source_pack': 'Characters · Robot',
                                   'animations': {'idleaim': clip, 'walkingshoot': clip}})
        self.assertEqual('walkingshoot', actions['walk']['clip'])
        self.assertEqual('walk', actions['run']['fallback'])
        self.assertFalse(actions['idle']['loop'])
        self.assertNotIn('sit', actions)
        self.assertEqual({}, runtime_actions({'kind': 'char', 'source_pack': 'Unreviewed', 'animations': {'attack': clip}}))
        with self.assertRaises(ValueError): runtime_actions({'kind': 'char', 'source_pack': 'Characters · Robot', 'animations': {'attack': clip}})

    def test_native_action_frames_are_explicit(self):
        actions = runtime_actions({'kind': 'char', 'frames': 9})
        self.assertEqual((6, 1, False), (actions['sit']['first_frame'], actions['sit']['frame_count'], actions['sit']['loop']))
        self.assertEqual('walk', actions['run']['fallback'])

    def test_explicit_family_dimensions(self):
        value = family_metadata({"source_pack": "Village buildings", "source_name": "round_cottage_voyager_dither/sun"})
        self.assertEqual("supplemental/village/round_cottage", value["family_id"])
        self.assertEqual("voyager_dither", value["palette_id"])
        self.assertEqual("sun", value["lighting_id"])
        other = family_metadata({"source_pack": "Village buildings", "source_name": "round_cottage_annex_voyager_dither/sun"})
        self.assertNotEqual(value["family_id"], other["family_id"])
        self.assertEqual("16bit_dither", family_metadata({"source_pack": "Bonsai trees", "source_name": "azalea_pink_16-bit_dither/studio"})["palette_id"])

    def test_unknown_packs_and_ambiguous_names_not_merged(self):
        self.assertEqual({}, family_metadata({"source_pack": "Custom imports", "source_name": "cottage_nopalette/studio"}))
        with self.assertRaises(ValueError): family_metadata({"source_pack": "Village buildings", "source_name": "mystery_palette/studio"})

    def test_animation_is_distinct_from_directions_and_states(self):
        self.assertEqual("animated_sprite", sprite_status({"kind": "char", "frames": 9, "directions": {"SE": {}}})["animation_status"])
        self.assertEqual("directional_sprite", sprite_status({"kind": "build", "frames": 2, "directions": {"SE": {}, "SW": {}}})["animation_status"])
        self.assertEqual("directional_sprite", sprite_status({"directions": {"0": {"frames": 1}, "45": {"frames": 1}}})["animation_status"])
        self.assertEqual("static_sprite", sprite_status({"directions": {"SE": {}}})["animation_status"])

    def test_rig_is_not_animation(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "model.gltf"
            path.write_text(json.dumps({"skins": [{}], "animations": []}))
            self.assertEqual("rigged_without_clips", mesh_status([path])["animation_status"])
            path.write_text(json.dumps({"skins": [{}], "animations": [{"name": "Walk"}]}))
            self.assertEqual({"animation_status": "animated_mesh", "supplied_clips": ["Walk"]}, mesh_status([path]))
            path.write_text("{}")
            self.assertEqual("static_mesh", mesh_status([path])["animation_status"])


if __name__ == "__main__": unittest.main()
