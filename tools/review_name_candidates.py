"""Create source-art/name review sheets; never infer or publish subject names."""
from pathlib import Path
import argparse
import json
import math
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'output/verification/asset_expansion/I04'

def sheets(pack, remaining=False):
    registry=json.loads((ROOT/'resources/catalog/imported_registry.json').read_text())['items']
    names=json.loads((ROOT/'resources/catalog/reviewed_names.json').read_text())['assets']
    items=[(ident,item) for ident,item in registry.items() if item['source_pack']==pack and (not remaining or '2d:'+ident not in names)]
    key=''.join(c if c.isalnum() else '_' for c in pack)
    OUT.mkdir(parents=True,exist_ok=True);(OUT/'.gdignore').touch()
    (OUT/f'inventory_full_{key}.json').write_text(json.dumps(items,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for page in range(math.ceil(len(items)/36)):
        batch=items[page*36:page*36+36]
        sheet=Image.new('RGB',(1200,math.ceil(len(batch)/6)*170),(225,230,235));draw=ImageDraw.Draw(sheet)
        for index,(ident,item) in enumerate(batch):
            view=item['directions'].get('SE',next(iter(item['directions'].values())))
            raw=view['file'];path=ROOT/'assets'/raw.removeprefix('../../') if raw.startswith('../../') else ROOT/'assets/pixel_isometric'/raw
            with Image.open(path) as source:art=source.convert('RGBA').crop((0,0,view['frame_width'],view['frame_height']))
            art.thumbnail((190,120),Image.Resampling.NEAREST)
            if max(art.size)<60:art=art.resize((art.width*2,art.height*2),Image.Resampling.NEAREST)
            x=index%6*200;y=index//6*170
            draw.text((x+3,y+3),str(page*36+index)+' '+item['display_name'][:23],fill='black')
            sheet.paste(art,(x+(200-art.width)//2,y+24+(120-art.height)//2),art)
            draw.text((x+3,y+148),item['source_name'].replace('\\','/').split('/')[-1][:27],fill='black')
        sheet.save(OUT/f'candidates_{key}_{page}.png')
    print(pack,len(items),'review candidates;',math.ceil(len(items)/36),'sheets')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--pack',required=True);parser.add_argument('--remaining',action='store_true')
    args=parser.parse_args();sheets(args.pack,args.remaining)
