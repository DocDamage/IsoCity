"""Audit that the I04 overlay changes descriptions only, plus review sheets."""
from pathlib import Path
import hashlib
import json
import math
import zipfile
from PIL import Image, ImageDraw
from compile_asset_metadata import compile_metadata
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'output/verification/asset_expansion/I04'

def main():
    compile_metadata(check=True)
    hashes = json.loads((OUT/'baseline/sha256.json').read_text())
    for relative in ('resources/catalog/catalog_registry.json', 'resources/catalog/imported_registry.json', 'resources/catalog/reviewed_registry.json'):
        assert hashlib.sha256((ROOT/relative).read_bytes()).hexdigest() == hashes[relative], relative
    with zipfile.ZipFile(OUT/'baseline/originals.zip') as archive:
        original = json.loads(archive.read('resources/catalog/asset_metadata.json'))['assets']
    current = json.loads((ROOT/'resources/catalog/asset_metadata.json').read_text())['assets']
    names = json.loads((ROOT/'resources/catalog/reviewed_names.json').read_text())['assets']
    assert set(original) == set(current)
    for ident, entry in current.items():
        assert {k:v for k,v in entry.items() if ident not in names or k not in ('display_name','aliases','name_key','name_source')} == original[ident], ident
    registry = {}
    for filename in ['catalog_registry.json','imported_registry.json']:
        registry.update(json.loads((ROOT/'resources/catalog'/filename).read_text(encoding='utf-8'))['items'])
    items = list(names.items())
    for page in range(math.ceil(len(items)/20)):
        batch=items[page*20:page*20+20]
        sheet=Image.new('RGB',(1200,math.ceil(len(batch)/4)*190),(225,230,235));draw=ImageDraw.Draw(sheet)
        for i,(ident,entry) in enumerate(batch):
            source=registry[ident.removeprefix('2d:')];view=source['directions'].get('SE',next(iter(source['directions'].values())))
            raw=view['file'];path=ROOT/'assets'/raw.removeprefix('../../') if raw.startswith('../../') else ROOT/'assets/pixel_isometric'/raw
            with Image.open(path) as image:art=image.convert('RGBA').crop((0,0,view['frame_width'],view['frame_height']))
            art.thumbnail((280,120),Image.Resampling.NEAREST)
            if max(art.size)<64:art=art.resize((art.width*2,art.height*2),Image.Resampling.NEAREST)
            x=i%4*300;y=i//4*190
            draw.text((x+4,y+4),entry['display_name'],fill='black');sheet.paste(art,(x+(300-art.width)//2,y+30),art)
            draw.text((x+4,y+160),str(entry['source_name'] or ident.removeprefix('2d:')).replace('\\','/').split('/')[-1],fill='black')
        sheet.save(OUT/f'reviewed_names_{page}.png')
    result={'reviewed_names':len(names),'catalog_entries':len(current),'original_ids_and_catalogs':'unchanged','metadata_changes':'display_name, aliases, name_key, and missing-source-name provenance only'}
    (OUT/'name_verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print('PASS:',result)

if __name__=='__main__':main()
