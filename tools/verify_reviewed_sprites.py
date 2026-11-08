"""Check I03 source fidelity and write reproducible source/prepared review sheets."""
from pathlib import Path
from collections import defaultdict
import hashlib
import json
import math
from PIL import Image,ImageDraw
import prepare_reviewed_sprites as build

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/I03'


def verify():
    build.prepare(check=True)
    for filename in ('sha256.json','native_sha256.json'):
        for name,expected in json.loads((OUT/'baseline'/filename).read_text()).items():
            if name.startswith(('assets/','scenes/')) or name in ('resources/catalog/imported_registry.json','resources/catalog/catalog_registry.json'):
                assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==expected,name
    manifest=json.loads((ROOT/build.MANIFEST).read_text())
    registry=json.loads((ROOT/build.REGISTRY).read_text())
    groups=defaultdict(list)
    for ident,item in registry['items'].items():
        definition=manifest['assets'][item['reviewed_key']]
        for direction,view in item['directions'].items():
            path=ROOT/'assets'/view['file'][6:]
            with Image.open(path) as image:
                assert image.size==(view['frame_width']*view['frames'],view['frame_height'])
                for index in range(view['frames']):
                    assert image.crop((index*view['frame_width'],0,(index+1)*view['frame_width'],view['frame_height'])).getchannel('A').getbbox(),(ident,direction,index)
        groups[item['source_pack']+('_tiles' if item.get('surface') else '')].append((ident,item))
    for group,items in groups.items():
        for page in range(math.ceil(len(items)/30)):
            part=items[page*30:page*30+30];sheet=Image.new('RGB',(1200,math.ceil(len(part)/5)*190),(231,234,238));draw=ImageDraw.Draw(sheet)
            for index,(ident,item) in enumerate(part):
                view=item['directions'].get('SE',next(iter(item['directions'].values())))
                with Image.open(ROOT/'assets'/view['file'][6:]) as source:art=source.convert('RGBA').crop((0,0,view['frame_width'],view['frame_height']))
                factor=min(2,220/art.width,135/art.height);art=art.resize((max(1,round(art.width*factor)),max(1,round(art.height*factor))),Image.Resampling.NEAREST)
                x=index%5*240;y=index//5*190;sheet.paste(art,(x+(240-art.width)//2,y+24+(135-art.height)//2),art)
                draw.text((x+3,y+3),item['reviewed_key'][-33:],fill='black');draw.text((x+3,y+162),f"{view['frame_width']}x{view['frame_height']} f{view['frames']} / {len(item['directions'])} views",fill='black')
            sheet.save(OUT/('prepared_'+group.replace(' ','_')+'_'+str(page)+'.png'))
    for key in ['myart_campfire','myart_treasure_chest','rodwan_flag_0','rodwan_flag_1','rodwan_flag_2','village_coffee_door','village_fast_food_door','sailing_ship_turntable','village_tree_wind_29','village_tree_wind_30','myart_grass_wind_31','myart_grass_wind_35']:
        item=registry['items'][build.identity(key)];samples=[]
        for direction,view in item['directions'].items():
            with Image.open(ROOT/'assets'/view['file'][6:]) as strip:
                for index in range(view['frames']):samples.append((direction,index,strip.convert('RGBA').crop((index*view['frame_width'],0,(index+1)*view['frame_width'],view['frame_height']))))
        sheet=Image.new('RGB',(8*150,math.ceil(len(samples)/8)*170),(226,230,234));draw=ImageDraw.Draw(sheet)
        for index,(direction,frame,art) in enumerate(samples):
            art.thumbnail((140,130),Image.Resampling.NEAREST)
            if max(art.size)<65:art=art.resize((art.width*2,art.height*2),Image.Resampling.NEAREST)
            x=index%8*150;y=index//8*170;sheet.paste(art,(x+(150-art.width)//2,y+25+(135-art.height)//2),art);draw.text((x+3,y+3),f'{direction} {frame+1}',fill='black')
        sheet.save(OUT/('frames_'+key+'.png'))
    result={'reviewed_legacy_entries':len(manifest['reviews']),'new_definitions':len(registry['items']),'source_fidelity':'passed','sheets_written':True}
    (OUT/'image_verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print('PASS:',result)


if __name__=='__main__':verify()
