from pathlib import Path
import copy,json,tempfile,unittest
from validate_asset_semantics import validate_semantics
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/U16'

class SemanticsValidation(unittest.TestCase):
    def setUp(self):
        OUT.mkdir(parents=True,exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(dir=OUT);self.root=Path(self.temp.name)
        self.path=self.root/'resources/catalog/asset_semantics.json';self.path.parent.mkdir(parents=True)
        self.value={'version':1,'groups':{'classroom':'Classroom'},'assets':{'model:chair':{'tags':['school'],'tasks':['furnish classroom'],'aliases':['seat'],'use_groups':['classroom'],'source_note':'Reviewed supplied chair artwork'}}}
    def tearDown(self):self.temp.cleanup()
    def write(self,value):self.path.write_text(json.dumps(value),encoding='utf-8')
    def test_valid_reviewed_overlay_is_read_only(self):
        self.write(self.value);before=(self.path.read_bytes(),self.path.stat().st_mtime_ns)
        validate_semantics(self.root,{'model:chair'})
        self.assertEqual(before,(self.path.read_bytes(),self.path.stat().st_mtime_ns))
    def test_unknown_identity_or_use_rejected(self):
        for mutate in ('id','group'):
            value=copy.deepcopy(self.value)
            if mutate=='id':value['assets']['unknown']=value['assets'].pop('model:chair')
            else:value['assets']['model:chair']['use_groups']=['unknown']
            self.write(value)
            with self.assertRaises(ValueError):validate_semantics(self.root,{'model:chair'})
    def test_malformed_and_unbounded_fields_rejected(self):
        for invalid in (False,{},['school','school'],['x'*241],['school']*65,[4],[' ']):
            value=copy.deepcopy(self.value);value['assets']['model:chair']['tags']=invalid;self.write(value)
            with self.assertRaises(ValueError):validate_semantics(self.root,{'model:chair'})
    def test_provenance_and_version_required(self):
        for mutate in ('source','version','bool_version','long_source'):
            value=copy.deepcopy(self.value)
            if mutate=='source':value['assets']['model:chair'].pop('source_note')
            elif mutate=='version':value['version']=2
            elif mutate=='bool_version':value['version']=True
            else:value['assets']['model:chair']['source_note']='x'*1001
            self.write(value)
            with self.assertRaises(ValueError):validate_semantics(self.root,{'model:chair'})

if __name__=='__main__':unittest.main()
