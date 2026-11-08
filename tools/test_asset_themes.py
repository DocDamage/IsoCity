from pathlib import Path
import copy,json,tempfile,unittest
from unittest import mock
from compile_asset_themes import ROOT, THEMES, catalog_assets, compile_themes

class ThemeCompilerTest(unittest.TestCase):
    def setUp(self):
        out=ROOT/'output/verification/asset_expansion/U01';out.mkdir(parents=True,exist_ok=True)
        self.folder=tempfile.TemporaryDirectory(dir=out);self.addCleanup(self.folder.cleanup);self.root=Path(self.folder.name)
        (self.root/'resources/catalog').mkdir(parents=True)
        self.id='2d:fixture';self.definitions={key:{'label':key,'description':'Reviewed collection','icon':'build','preview_id':self.id} for key in THEMES}
        (self.root/'resources/catalog/catalog_registry.json').write_text(json.dumps({'items':{'fixture':{'category':'Props','source_pack':'Fixture'}}}))
        self.manifest={'version':1,'definitions':self.definitions,'packs':{'Fixture':{'themes':list(THEMES),'note':'Reviewed neutral artwork'}}}

    def write(self,manifest=None):
        (self.root/'resources/catalog/asset_themes.json').write_text(json.dumps(self.manifest if manifest is None else manifest))

    def test_many_themes_do_not_duplicate_asset_identity(self):
        self.write();result=compile_themes(self.root)
        self.assertEqual([self.id],list(result['assets']))
        self.assertEqual(list(THEMES),result['assets'][self.id]['themes'])

    def test_unknown_pack_stays_unclassified(self):
        path=self.root/'resources/catalog/imported_registry.json'
        path.write_text(json.dumps({'items':{'new':{'category':'Custom','source_pack':'Unknown'}}}))
        self.write();result=compile_themes(self.root)
        self.assertEqual([],result['assets']['2d:new']['themes'])
        self.assertIn('No reviewed',result['assets']['2d:new']['theme_note'])

    def test_exact_override_preserves_other_assets_and_pack_default(self):
        (self.root/'resources/catalog/imported_registry.json').write_text(json.dumps({'items':{'new':{'category':'Props','source_pack':'Fixture'}}}))
        self.manifest['assets']={'2d:new':{'themes':['village'],'note':'Reviewed specific subject'}}
        self.write();result=compile_themes(self.root)
        self.assertEqual(['village'],result['assets']['2d:new']['themes'])
        self.assertEqual(list(THEMES),result['assets'][self.id]['themes'])

    def test_invalid_tags_rules_ids_versions_and_previews_do_not_publish(self):
        self.write();compile_themes(self.root);path=self.root/'resources/catalog/asset_theme_metadata.json';good=path.read_bytes()
        cases=[]
        for invalid in [['village','village'],['typo'],True,None]:
            value=copy.deepcopy(self.manifest);value['packs']['Fixture']['themes']=invalid;cases.append(value)
        for field,invalid in [('version',True),('version',2),('definitions',{}),('packs',[])]:
            value=copy.deepcopy(self.manifest);value[field]=invalid;cases.append(value)
        value=copy.deepcopy(self.manifest);value['packs']['Missing']={'themes':[],'note':'Missing'};cases.append(value)
        value=copy.deepcopy(self.manifest);value['assets']={'2d:missing':{'themes':['space'],'note':'Missing'}};cases.append(value)
        value=copy.deepcopy(self.manifest);value['definitions']['space']['preview_id']='2d:missing';cases.append(value)
        cases.extend([[],None])
        for value in cases:
            (self.root/'resources/catalog/asset_themes.json').write_text(json.dumps(value))
            with self.assertRaises(ValueError):compile_themes(self.root)
            self.assertEqual(good,path.read_bytes())

    def test_idempotence_and_failed_replacement_keep_good_metadata(self):
        self.write();compile_themes(self.root);path=self.root/'resources/catalog/asset_theme_metadata.json';before=path.read_bytes();stamp=path.stat().st_mtime_ns
        compile_themes(self.root);compile_themes(self.root,check=True)
        self.assertEqual((before,stamp),(path.read_bytes(),path.stat().st_mtime_ns))
        self.manifest['packs']['Fixture']['note']='Re-reviewed note';self.write()
        with mock.patch('pathlib.Path.replace',side_effect=OSError('simulated failed write')):
            with self.assertRaises(OSError):compile_themes(self.root)
        self.assertEqual(before,path.read_bytes())

    def test_native_and_descriptor_pack_identity(self):
        path=self.root/'resources/catalog/catalog_registry.json'
        path.write_text(json.dumps({'items':{'city':{'category':'Buildings'},'rpg':{'category':'RPG_Props','directions':{'SE':{'file':'../../isometric_rpg_world/source.png'}}}}}))
        scene=self.root/'scenes/items_3d/HanX_School/Desk.tscn';scene.parent.mkdir(parents=True);scene.write_text('')
        model=self.root/'scenes/items_3d/Supplemental_Models/Fixture.tscn';model.parent.mkdir(parents=True);model.write_text('')
        (self.root/'resources/catalog/supplemental_registry.json').write_text(json.dumps({'models':{'3d:Supplemental_Models/Fixture':{'data':{'source_pack':'Reviewed models'}}}}))
        actual=catalog_assets(self.root)
        self.assertEqual('Pixel Isometric',actual['2d:city']['pack'])
        self.assertEqual('RPG World',actual['2d:rpg']['pack'])
        self.assertEqual('HanX_School',actual['3d:HanX_School/Desk']['pack'])
        self.assertEqual('Reviewed models',actual['3d:Supplemental_Models/Fixture']['pack'])

if __name__=='__main__':unittest.main()
