"""Review preparation invariants using original tiny images, no GPU required."""
from pathlib import Path
from unittest.mock import patch
import hashlib
import json
import tempfile
import unittest
from PIL import Image,ImageDraw
import prepare_reviewed_sprites as build


class ReviewedSpritesTest(unittest.TestCase):
    def test_legacy_import_does_not_reingest_generated_or_separately_managed_assets(self):
        from import_extra_assets import source_packs
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            for name in ['cars','reviewed_prepared','supplemental_prepared','supplemental_source','supplemental_models','custom_assets','editor','audio']:(root/name).mkdir()
            self.assertEqual(['cars'],[p.name for p in source_packs(root)])

    def fixture(self, root):
        (root/'resources/catalog').mkdir(parents=True)
        (root/'assets').mkdir()
        source=root/'assets/source.png'
        image=Image.new('RGBA',(8,4),'red'); ImageDraw.Draw(image).rectangle((4,0,7,3),fill='blue'); image.save(source)
        legacy={'Legacy':{'source_pack':'Fixture','source_name':'Original atlas','source_files':['res://assets/source.png']}}
        (root/'resources/catalog/imported_registry.json').write_text(json.dumps({'items':legacy}))
        manifest={'version':1,'reviews':{'2d:Legacy':{'content_kind':'atlas','note':'Two approved frames','source_sha256':{'res://assets/source.png':hashlib.sha256(source.read_bytes()).hexdigest()}}},
                  'assets':{'fixture':{'source_asset':'2d:Legacy','display_name':'Approved fixture','category':'Reviewed Fixture','views':{'SE':{'source':'res://assets/source.png','frames':[{'rect':[0,0,4,4]},{'rect':[4,0,4,4]}],'contact':[2,4],'footprint':[1,1]}}}},'replacements':{'2d:Legacy':['fixture']}}
        self.save(root,manifest)
        return manifest

    def save(self,root,manifest): (root/build.MANIFEST).write_text(json.dumps(manifest))

    def test_idempotence_grouping_and_unchanged_legacy(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);self.fixture(root)
            before=(root/'resources/catalog/imported_registry.json').read_bytes()
            result=build.prepare(root); item=result['items']['Reviewed_fixture']
            self.assertEqual(['2d:Reviewed_fixture'],result['legacy_content']['2d:Legacy']['replacement_ids'])
            view=item['directions']['SE'];self.assertEqual((2,[2,-12]),(view['frames'],view['origin']))
            self.assertEqual('reviewed source contact and virtual footprint',view['grid_method'])
            with Image.open(root/'assets/reviewed_prepared/Reviewed_fixture_SE.png') as strip:
                self.assertEqual((8,4),strip.size);self.assertEqual((255,0,0,255),strip.getpixel((0,0)));self.assertEqual((0,0,255,255),strip.getpixel((4,0)))
            files={p:(p.read_bytes(),p.stat().st_mtime_ns) for p in root.rglob('*') if p.is_file()}
            build.prepare(root);build.prepare(root,check=True)
            self.assertEqual(files,{p:(p.read_bytes(),p.stat().st_mtime_ns) for p in files})
            self.assertEqual(before,(root/'resources/catalog/imported_registry.json').read_bytes())

    def test_opaque_flat_tiles_are_valid_and_keep_padding(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);manifest=self.fixture(root)
            config=manifest['assets']['fixture'];config.update(ground=True,layer='Ground')
            config['views']['SE']['frames']=[{'rect':[0,0,4,4]}];self.save(root,manifest)
            result=build.prepare(root)
            self.assertTrue(result['items']['Reviewed_fixture']['behavior']['ground'])
            with Image.open(root/'assets/reviewed_prepared/Reviewed_fixture_SE.png') as image:self.assertEqual((4,4),image.size)

    def test_source_changes_require_review_and_keep_existing_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);self.fixture(root);build.prepare(root)
            good=(root/build.REGISTRY).read_bytes()
            Image.new('RGBA',(8,4),'green').save(root/'assets/source.png')
            with self.assertRaisesRegex(ValueError,'Source changed'):build.prepare(root)
            self.assertEqual(good,(root/build.REGISTRY).read_bytes())

    def test_invalid_crops_contacts_frames_and_view_paths_fail_before_publication(self):
        for field,value in [('frames',[{'rect':[6,0,4,4]}]),('frames',[{'rect':[0,0,4,4],'source_frame':True}]),('contact',[True,1]),('contact',[float('nan'),0]),('footprint',[0,1])]:
            with self.subTest(field=field,value=value),tempfile.TemporaryDirectory() as folder:
                root=Path(folder);manifest=self.fixture(root);manifest['assets']['fixture']['views']['SE'][field]=value;self.save(root,manifest)
                with self.assertRaises(ValueError):build.prepare(root)
                self.assertFalse((root/build.REGISTRY).exists())
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);manifest=self.fixture(root);view=manifest['assets']['fixture']['views'].pop('SE');manifest['assets']['fixture']['views']['../../outside']=view;self.save(root,manifest)
            with self.assertRaises(ValueError):build.prepare(root)

    def test_border_key_preserves_enclosed_white_details(self):
        image=Image.new('RGBA',(7,7),'white');ImageDraw.Draw(image).rectangle((1,1,5,5),fill='black');image.putpixel((3,3),(255,255,255,255))
        cleaned=build.clear_border_color(image,[255,255,255])
        self.assertEqual(0,cleaned.getpixel((0,0))[3]);self.assertEqual(255,cleaned.getpixel((3,3))[3]);self.assertEqual((255,255,255,255),image.getpixel((0,0)))

    def test_failed_replacement_retains_good_image_and_registry(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);manifest=self.fixture(root);build.prepare(root)
            path=root/'assets/reviewed_prepared/Reviewed_fixture_SE.png';good=path.read_bytes();registry=(root/build.REGISTRY).read_bytes()
            manifest['assets']['fixture']['views']['SE']['frames'].reverse();self.save(root,manifest)
            with patch('prepare_reviewed_sprites.os.replace',side_effect=PermissionError('locked')):
                with self.assertRaises(PermissionError):build.prepare(root)
            self.assertEqual(good,path.read_bytes());self.assertEqual(registry,(root/build.REGISTRY).read_bytes())

    def test_existing_reviewed_ids_cannot_disappear(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);manifest=self.fixture(root);build.prepare(root)
            manifest['assets']={};manifest['replacements']={};self.save(root,manifest)
            with self.assertRaisesRegex(ValueError,'remain recoverable'):build.prepare(root)


if __name__=='__main__':unittest.main()
