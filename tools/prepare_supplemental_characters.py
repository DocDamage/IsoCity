"""Recover directional clips, retain their timing, and assemble reusable character families."""
from pathlib import Path
from collections import defaultdict
import json
import re
import statistics
import sys
import argparse
from PIL import Image
import numpy as np
from ingest_supplemental_assets import ROOT, RAW
from prepare_supplemental_assets import Builder, human, res, write

COMPASS = ['SW','W','NW','N','NE','E','SE','S']
NAMED = {'Down':'S','DownLeft':'SW','DownRight':'SE','Left':'W','Right':'E','Up':'N','UpLeft':'NW','UpRight':'NE'}


def read_frames(path, cell):
    sheet = Image.open(path).convert('RGBA')
    metadata = path.with_suffix('.json')
    raw = None
    if metadata.exists() and metadata.stat().st_size:
        try: raw = json.loads(metadata.read_text(encoding='utf-8-sig'))
        except (ValueError, UnicodeError): pass
    if isinstance(raw, dict) and raw.get('frames'):
        values = raw['frames'].values() if isinstance(raw['frames'],dict) else raw['frames']
        frames, times = [], []
        for value in values:
            rect = value['frame']; x,y,w,h = (int(rect[k]) for k in ('x','y','w','h'))
            frames.append(sheet.crop((x,y,x+w,y+h)))
            duration = float(value.get('duration',0))
            if duration>0: times.append(duration if duration<1 else duration/1000)
        fps = 1/statistics.mean(times) if times else float(raw.get('meta',{}).get('frameAnimations',[{'fps':12}])[0].get('fps',12))
        return frames, fps, 'supplied frame metadata'
    width,height = cell
    if sheet.width%width or sheet.height%height: raise ValueError(f'Unrecognized frame grid: {path}')
    frames = [sheet.crop((x,y,x+width,y+height)) for y in range(0,sheet.height,height) for x in range(0,sheet.width,width)]
    last = max((i for i,frame in enumerate(frames) if frame.getbbox()),default=-1)
    frames = frames[:last+1]
    gif = path.with_name(path.stem.replace('__','_')+'.gif')
    fps = 12.0; timing = '12fps fallback; source timing absent'
    if gif.exists():
        preview = Image.open(gif); durations=[]
        for index in range(preview.n_frames):
            preview.seek(index); durations.append(preview.info.get('duration',80))
        if durations and sum(durations)>0: fps=1000/statistics.mean(durations); timing='supplied GIF cadence'
    return frames,fps,timing


def pivot(frame):
    alpha=np.asarray(frame.getchannel('A'))
    box=frame.getbbox()
    if not box: return frame.width*.5,frame.height
    band=alpha[max(0,box[3]-5):box[3]]>32
    _,xs=np.where(band)
    return float(np.mean(xs)) if len(xs) else (box[0]+box[2])*.5,float(box[3])


def actor_scene(builder,family,clips,metadata):
    actions = list(clips)
    idle = next((a for a in actions if a.lower() in ['idle','idle1','iddle_001','readyidle','idleaim']),None)
    idle = idle or next((a for a in actions if 'idle' in a.lower() or 'iddle' in a.lower()),actions[0])
    walk = next((a for a in actions if a.lower() in ['walk','2hwalk','anim_walkwhd','walkfoward','walkforward','revision walk']),None)
    walk = walk or next((a for a in actions if 'walk' in a.lower() and not any(s in a.lower() for s in ['back','strafe'])),idle)
    animations = {re.sub(r'[^a-z0-9_]+','_',a.lower()):{'directions':builder.items[ident]['directions'],
                                                    'fps':builder.items[ident]['fps'],'scale':builder.items[ident]['default_scale'],'loop':True}
                  for a,ident in clips.items()}
    animations['idle']=animations[re.sub(r'[^a-z0-9_]+','_',idle.lower())]
    animations['walk']=animations[re.sub(r'[^a-z0-9_]+','_',walk.lower())]
    original=builder.items[clips[idle]]
    idle_view=original['directions'].get('SE',next(iter(original['directions'].values())))
    atlas=Image.open(ROOT/'assets'/idle_view['file'].removeprefix('../../')).convert('RGBA')
    x,y,_,height=idle_view['region']; frame=atlas.crop((x,y,x+idle_view['frame_width'],y+height))
    box=frame.getbbox(); visible_height=max(1,box[3]-box[1]) if box else height
    visual_ratio=28/(visible_height*original['default_scale'])
    # Normalize reusable citizens; standalone action clips preserve source proportions.
    for animation in {id(value):value for value in animations.values()}.values():
        animation['scale']*=visual_ratio
    ident=original['name']+'_Character'; item=json.loads(json.dumps(original)); item['name']=ident
    item['display_name']=family+' · Character'; item['kind']='char'; item['animations']=animations
    item['actor_visual_ratio']=visual_ratio
    for view in item['directions'].values():
        w,d=view['footprint']; ox,oy=view['origin']
        view['grid_contact']=[ox+16*(w-d)/visual_ratio,oy+8*(w+d)/visual_ratio]
    item['behavior']={**original['behavior'],'character':True,'citizen_appearance':True}
    scene=ROOT/'scenes/items/Supplemental'/Path(original['scene_path']).parent.name/(ident+'.tscn')
    item['scene_path']=res(scene); item['import_tags']+=['character','idle','walk','citizen appearance']
    item['character_actions']=actions; item.update(metadata)
    builder.items[ident]=item
    view=item['directions'].get('SE',next(iter(item['directions'].values()))); area=view['region']; origin=view['origin']; scale=item['default_scale']
    preferred='SE' if 'SE' in item['directions'] else next(iter(item['directions']))
    write(scene,f'''[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/iso_character.gd" id="1"]
[ext_resource type="Texture2D" path={json.dumps('res://assets/'+view['file'].removeprefix('../../'))} id="2"]

[sub_resource type="AtlasTexture" id="AtlasTexture_idle"]
atlas = ExtResource("2")
region = Rect2({area[0]}, {area[1]}, {area[2]}, {area[3]})
filter_clip = true

[sub_resource type="CircleShape2D" id="BodyShape"]
radius = {4/max(.001,scale)}

[node name={json.dumps(ident)} type="CharacterBody2D"]
scale = Vector2({scale}, {scale})
collision_layer = 0
collision_mask = 1
script = ExtResource("1")
item_id = {json.dumps(ident)}
direction = {json.dumps(preferred)}
directions_data = {json.dumps(item['directions'])}
origin_offset = Vector2({origin[0]}, {origin[1]})

[node name="Sprite2D" type="Sprite2D" parent="."]
texture = SubResource("AtlasTexture_idle")
centered = false
offset = Vector2({-origin[0]}, {-origin[1]})
hframes = {view['frames']}

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("BodyShape")
''')
    builder.stats['character_families']+=1
    print(f'{family}: {len(clips)} clips, reusable idle/walk character',flush=True)


def wanderer(builder):
    roots=RAW/'Isometric_Wanderer'
    release=next(roots.glob('TalesOfTimelords*_unpacked'))
    release=next(p for p in release.iterdir() if p.is_dir())
    revision=next(roots.glob('Revison*_unpacked')); revision=next(p for p in revision.iterdir() if p.is_dir())
    pack='Characters · Eldrin Vaelor'; metadata=builder.notice(pack,release,restricted=True,author='Mudassir Khan')
    directions={'Down':'SE','Left':'SW','Right':'NE','Up':'NW'}; idle_views={}; walks={}; original_walks={}; files=[]
    for name,direction in directions.items():
        idle=next((release/'Character_Idle_Sheet').glob(name+'*.png')); idle_views[direction]=[Image.open(idle).convert('RGBA')]; files.append(res(idle))
        for source,output in [(revision,walks),(release,original_walks)]:
            folder=next(p for p in (source/'Walking_Animations').iterdir() if p.is_dir() and p.name.startswith(name))
            paths=sorted(folder.glob('*.png')); output[direction]=[Image.open(path).convert('RGBA') for path in paths]; files.extend(res(path) for path in paths)
    anchors={direction:(32,52) for direction in directions.values()}
    behavior={'layer':'Characters','building':False,'door':False,'vehicle':False,'ground':False,'collision':'none','walk':{'height':1.8}}
    clips={}
    for name,views in [('Idle',idle_views),('Revision walk',walks),('Original walk',original_walks)]:
        clips[name]=builder.sprite(pack,name,'Eldrin Vaelor · '+name,views,anchors=anchors,category='Characters',fps=8,sources=files,metadata=metadata,behavior=behavior)
    actor_scene(builder,'Eldrin Vaelor',clips,metadata)
    icon_license=next(release.rglob('COMMERCIAL LICENSE.txt'))
    icon_metadata={'author':'Mudassir Khan','source_url':'https://twitter.com/MudassirKh38273','license':'See supplied commercial license; asset-file redistribution prohibited','license_files':[res(icon_license)],'source_export_allowed':False}
    write(ROOT/'assets/supplemental_prepared/RPG_icons/LICENSE.txt',icon_license.read_text(encoding='utf-8'))
    for path in sorted((release/'Gift').rglob('*.png')):
        image=Image.open(path).convert('RGBA')
        if image.width>64 or image.height>64 or image.width!=image.height: continue
        builder.sprite('RPG icons',path.relative_to(release/'Gift').as_posix(),human(path.stem),{'SE':[image]},
                       anchors={'SE':(image.width*.5,image.height)},category='Icons',sources=[res(path)],metadata=icon_metadata,
                       behavior={'layer':'Decorations','building':False,'door':False,'vehicle':False,'ground':False,'collision':'none'})


def main():
    sys.stdout.reconfigure(encoding='utf-8'); parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--wanderer-only',action='store_true'); args=parser.parse_args(); builder=Builder(existing=True)
    if args.wanderer_only:
        wanderer(builder); builder.save()
        from compile_asset_metadata import compile_metadata
        compile_metadata()
        print(json.dumps(dict(builder.stats)),flush=True); return
    old={ident for ident,item in builder.items.items() if item['source_pack'].startswith('Characters · ')}
    builder.items={ident:item for ident,item in builder.items.items() if ident not in old}; builder.signatures={item['content_hash']:ident for ident,item in builder.items.items()}
    families=defaultdict(lambda:defaultdict(dict))
    sources=[('hormelz_characters/8 Directional Girl Character','Directional girl',256),
             ('hormelz_characters/businessman','Businessman',256),
             ('hormelz_characters/Drone Robot','Robot',256),
             ('hormelz_characters/Great Sword Knight Characte','Great sword knight',256),
             ('hormelz_characters/Orange Shirt Girl','Orange shirt girl',256),
             ('Melee_Character','Boxer',126)]
    for folder_name,label,width in sources:
        folder=RAW/folder_name
        for path in sorted(folder.rglob('*.png')):
            if label=='Orange shirt girl':
                match=re.match(r'GirlSample_(.+)_(DownLeft|DownRight|UpLeft|UpRight|Down|Left|Right|Up)$',path.stem)
                if not match: continue
                action=match[1]; direction=NAMED[match[2]]; family=label
            else:
                match=re.match(r'(.+)_dir([1-8])$',path.stem)
                if not match: continue
                direction=COMPASS[int(match[2])-1]; family=label
                if label=='Robot':
                    parts=re.match(r'LowPolyManny_(Blue|Red|export)_rig_(.+)',match[1]); family={'Blue':'Blue robot','Red':'Red robot','export':'Robot'}[parts[1]]; action=parts[2]
                elif label=='Boxer': action=match[1].removeprefix('Boxer_').lstrip('_')
                else: action=path.parent.name
            frames,fps,timing=read_frames(path,(width,132 if label=='Boxer' else width))
            if frames: families[family][action][direction]=(frames,fps,timing,path)
    for family,actions in families.items():
        pack='Characters · '+family
        folder=RAW/('Melee_Character' if family=='Boxer' else 'hormelz_characters')
        metadata=builder.notice(pack,folder)
        idle=next((a for a in actions if a.lower() in ['idle','idle1','iddle_001','readyidle','idleaim']),None)
        idle=idle or next((a for a in actions if 'idle' in a.lower() or 'iddle' in a.lower()),next(iter(actions)))
        pivots={direction:pivot(value[0][0]) for direction,value in actions[idle].items()}
        clips={}
        for action,views in actions.items():
            prepared={}; anchors={}; source_paths=[]; cadences=[]; timing=[]
            for direction,(frames,fps,origin,path) in views.items():
                ratio=.5 if family=='Boxer' else .25; w,h=frames[0].size; target=(round(w*ratio),round(h*ratio))
                prepared[direction]=[frame.resize(target,Image.Resampling.NEAREST) for frame in frames]
                point=pivots.get(direction,pivot(frames[0])); anchors[direction]=(point[0]*ratio,point[1]*ratio)
                source_paths.append(res(path)); cadences.append(fps); timing.append(origin)
            ident=builder.sprite(pack,action,family+' · '+human(action),prepared,anchors=anchors,category='Characters',
                                 fps=statistics.mean(cadences),sources=source_paths,metadata={**metadata,'source_timing':sorted(set(timing))},
                                 behavior={'layer':'Characters','building':False,'door':False,'vehicle':False,'ground':False,'collision':'none','walk':{'height':1.8}})
            clips[action]=ident
        actor_scene(builder,family,clips,metadata)
    wanderer(builder); builder.save()
    from compile_asset_metadata import compile_metadata
    compile_metadata()
    print(json.dumps(dict(builder.stats)),flush=True)


if __name__=='__main__': main()
