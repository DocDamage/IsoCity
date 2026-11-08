"""Task audit against the preserved U01 baseline, separate from normal tests."""
from pathlib import Path
import hashlib,json,collections
from compile_asset_themes import ROOT,catalog_assets,compile_themes,THEMES
OUT=ROOT/'output/verification/asset_expansion/U01'

def main():
    result=compile_themes(check=True)
    original=json.loads((OUT/'baseline/library.json').read_text(encoding='utf-8'))['assets']
    hashes=json.loads((OUT/'baseline/sha256.json').read_text(encoding='utf-8'))
    for relative,digest in hashes.items():
        if relative.startswith('resources/catalog/'):
            assert hashlib.sha256((ROOT/relative).read_bytes()).hexdigest()==digest,relative
    actual=catalog_assets(ROOT)
    assert set(actual)==set(original)==set(result['assets'])
    for ident,item in actual.items():assert item['pack']==original[ident]['pack'],ident
    counts=collections.Counter(theme for item in result['assets'].values() for theme in item['themes'])
    assert set(counts)==set(THEMES)
    stats={'assets':len(actual),'source_groups':len({v['pack'] for v in actual.values()}),'theme_memberships':dict(counts),'unclassified':sum(not item['themes'] for item in result['assets'].values()),'overlapping_assets':sum(len(item['themes'])>1 for item in result['assets'].values()),'original_catalogs_and_existing_metadata':'byte-identical','pack_identity':'unchanged'}
    (OUT/'theme_verification.json').write_text(json.dumps(stats,indent=2)+'\n',encoding='utf-8')
    print('PASS:',stats)

if __name__=='__main__':main()
