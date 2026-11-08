"""Compile supplemental asset roles and interactions into explicit runtime metadata."""
from pathlib import Path
import json
import math
import re
import sys
from ingest_supplemental_assets import ROOT, REPORT
from prepare_supplemental_assets import write, REGISTRY
from compile_functional_defaults import compile_defaults
from compile_asset_metadata import compile_metadata

YAW = {'SW':0,'S':45,'SE':90,'E':135,'NE':180,'N':225,'NW':270,'W':315}


def read(name): return json.loads((ROOT/'resources/catalog'/name).read_text(encoding='utf-8'))


def main():
    sys.stdout.reconfigure(encoding='utf-8'); registry=read('supplemental_registry.json')
    props=read('props.json'); roles=read('citizen_roles.json'); business=read('businesses.json')
    driving=read('driving.json'); weather=read('weather.json'); themes=read('neighborhoods.json'); economy=read('economy.json')
    counts={'seats':0,'appliances':0,'switches':0,'businesses':0,'homes':0,'workplaces':0,'drivable_cars':0,'foliage':0}
    village=[]
    for ident,item in registry['items'].items():
        asset='2d:'+ident; key=item['source_name'].lower(); pack=item['source_pack']
        props['assets'].pop(asset,None); roles.pop(asset,None); business.pop(asset,None); driving['assets'].pop(asset,None); weather['foliage'].pop(asset,None); economy['assets'].pop(asset,None)
        if pack.endswith(' kit'):
            if re.search(r'(?:^|_)(chair|stool|bench|bean_bag)(?:_|$)',key) and 'workbench' not in key:
                views={}
                for direction in item['directions']:
                    angle=math.radians(float(direction)); ahead=[-math.sin(angle)*1.2,0,math.cos(angle)*1.2]
                    views[direction]={'point':[0,.5,0],'approach':ahead,'end':ahead}
                props['assets'][asset]={'kind':'seat','views':views}; counts['seats']+=1
            elif re.search(r'washer|dryer|washing_machine|coffee_machine|microwave|toaster|stove|treadmill|exercise_bike|rowing_machine',key):
                props['assets'][asset]={'kind':'appliance','label':'Use '+item['display_name'].lower(),'duration':5}; counts['appliances']+=1
            elif re.search(r'(?:^|_)(campfire|lamp|lantern|flashlight|desk_fan)(?:_|$)',key):
                props['assets'][asset]={'kind':'switch','label':'Toggle '+item['display_name'].lower(),'effect':'lamp' if 'fan' not in key else 'machine'}; counts['switches']+=1
        if pack=='Village buildings':
            if any(name in key for name in ['cottage','house','longhouse']):roles[asset]='home';counts['homes']+=1
            elif item['behavior'].get('building'):roles[asset]='work';counts['workplaces']+=1
            if any(name in key for name in ['bakery','tavern','market_stall','apothecary']):
                business[asset]='cafe' if 'bakery' in key or 'tavern' in key else 'shop';roles[asset]='shop';counts['businesses']+=1
            if item['behavior'].get('building'):
                points={}
                for direction,view in item['directions'].items():
                    width,depth=view['footprint']; angle=math.radians(float(direction)); x,z=-math.sin(angle),math.cos(angle)
                    distance=1/max(abs(x)/(width*.5),abs(z)/(depth*.5),1e-9)
                    points[direction]={'point':[width*.5+x*distance,depth*.5+z*distance],
                                       'arrival':[width*.5+x*(distance+1),depth*.5+z*(distance+1)]}
                item['behavior']['entrance_anchor']={'views':points}
                if key.endswith('_nopalette/studio') and any(name in key for name in ['thatched_cottage','timber_frame_house','round_cottage','longhouse','farmhouse_barn','tavern_inn']):village.append(asset)
        if pack.startswith('Korean Street') and item['behavior'].get('building'):
            if 'house' in key:roles[asset]='home';counts['homes']+=1
            else:business[asset]='shop' if 'convenience' in key else 'cafe';roles[asset]='shop';counts['businesses']+=1
        if pack=='Water towers': economy['assets'][asset]={'construction':1800,'upkeep':20,'income':0}
        if pack.startswith('Flipped Fleet '):
            item['view_yaws']=YAW.copy(); driving['assets'][asset]={'view_yaws':YAW.copy()}; counts['drivable_cars']+=1
            for direction,view in item['directions'].items():
                angle=math.radians(YAW[direction]); width=math.ceil(4*abs(math.sin(angle))+2*abs(math.cos(angle))-.00001); depth=math.ceil(4*abs(math.cos(angle))+2*abs(math.sin(angle))-.00001)
                width=math.ceil(width/2)*2; depth=math.ceil(depth/2)*2
                view['footprint']=[width,depth];view['origin']=[64-8*(width-depth),75.5-4*(width+depth)]
                view['grid_contact']=[view['origin'][0]+16*(width-depth),view['origin'][1]+8*(width+depth)]
        if pack=='Bonsai trees':
            kind='evergreen' if any(name in key for name in ['pine','juniper','cedar','ficus','boxwood','jade','spruce']) else 'blossom' if any(name in key for name in ['blossom','azalea','wisteria','bougainvillea']) else 'deciduous'
            weather['foliage'][asset]=kind;counts['foliage']+=1
        scene=ROOT/item['scene_path'].removeprefix('res://'); text=scene.read_text(encoding='utf-8')
        text=re.sub(r'^directions_data = .+$','directions_data = '+json.dumps(item['directions']),text,flags=re.M);write(scene,text)
    for asset,descriptor in registry['models'].items():
        props['assets'].pop(asset,None);weather['foliage'].pop(asset,None)
        if descriptor['data']['source_pack']=='Arcade machines':
            props['assets'][asset]={'kind':'appliance','label':'Play arcade game','duration':6,'result':'Game completed'};counts['appliances']+=1
        elif descriptor['data']['source_pack']=='Deciduous trees':
            weather['foliage'][asset]='blossom' if 'blossom' in asset else 'deciduous';counts['foliage']+=1
    if village:
        themes['supplemental_village']={'label':'Village sprites','ground':'Grass','road_style':'brick','2d':village,'3d':village}
    for filename,value in [('supplemental_registry.json',registry),('props.json',props),('citizen_roles.json',roles),('businesses.json',business),('driving.json',driving),('weather.json',weather),('neighborhoods.json',themes),('economy.json',economy)]:write(ROOT/'resources/catalog'/filename,json.dumps(value,ensure_ascii=False,indent=2))
    compile_defaults()
    compile_metadata()
    write(REPORT/'interaction_manifest.json',json.dumps(counts,indent=2));write(REPORT/'prepared_manifest.json',json.dumps(registry,ensure_ascii=False,indent=2));print(json.dumps(counts),flush=True)


if __name__=='__main__':main()
