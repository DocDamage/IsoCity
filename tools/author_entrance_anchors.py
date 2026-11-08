"""Author catalog entrance points from the visually audited source contact sheets.

Sprite points below are hand-selected doorway thresholds in the audit sheet's
280x300 cells. Conversion records source pixels and logical ground coordinates.
Runtime code uses the resulting explicit catalog values, never these rules.
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CAT = ROOT / 'resources/catalog'
items = {}
for name in ('catalog_registry.json', 'imported_registry.json'):
    items.update(json.loads((CAT / name).read_text())['items'])
behavior = json.loads((CAT / 'asset_behaviors.json').read_text())
ids = ['2d:1', '2d:1-48X64', '2d:1_1', '2d:1_4', '2d:1_5', '2d:2', '2d:2-48X48', '2d:2_1', '2d:2_2', '2d:2tree', '2d:3', '2d:3-32X32', '2d:3_1', '2d:3_2', '2d:4-128X128', '2d:5', '2d:6', '2d:7', '2d:7_1', '2d:7_2', '2d:ATM_1', '2d:Apartment_Brick', '2d:Apartment_Building', '2d:Arcade', '2d:Bakery', '2d:Bakery_1', '2d:Bank', '2d:Barber_Shop', '2d:Basket', '2d:Bookstore', '2d:Burger_Diner', '2d:Clothing_Boutique', '2d:Coffee_Shop', '2d:Convenience_Store', '2d:Fance', '2d:Fance_-', '2d:Fast_Food', '2d:Fast_Food_Building', '2d:Fire_Station1_-_Copie', '2d:Flower_Shop', '2d:Gas_Station', '2d:Hopital', '2d:Hopital_-', '2d:House_Blue', '2d:House_Brick', '2d:House_Mint_Garage', '2d:House_Pink_Two_Story', '2d:House_White_Modern', '2d:House_Yellow', '2d:Ice_Cream_Parlor', '2d:Office_Tower', '2d:Pet_Shop', '2d:Pharmacy', '2d:Pizza_Place', '2d:Police', '2d:Police_Officer_1', '2d:Public_Library', '2d:Public_Library_-', '2d:Skyscrapers1', '2d:Skyscrapers2', '2d:Skyscrapers3', '2d:Skyscrapers4', '2d:Skyscrapers5', '2d:Supermarket', '2d:Supermarket_-', '2d:Supermarket_1', '2d:Toy_Store', '2d:ball', '2d:ball_1', '2d:bank', '2d:bank-golden', '2d:city_Hall', '2d:city_Hall_-', '2d:city_Hall_-_2', '2d:close', '2d:close_the_door', '2d:coffee', '2d:coffee_-', '2d:door-close', '2d:door-open', '2d:floor', '2d:hotel', '2d:hotel_-', '2d:house', '2d:isometric_football_pitch_tileset', '2d:isometric_football_pitch_tileset_1', '2d:open', '2d:open-door', '2d:open-door-', '2d:open-door-3', '2d:open-door3', '2d:open_door', '2d:open_door_1', '2d:open_door_2', '2d:open_door_3', '2d:open_door_4', '2d:open_door_5', '2d:open_the_door', '2d:open_the_door-re', '2d:open_the_door_1', '2d:prop_basketball_court_full', '2d:prop_field_center_circle', '2d:prop_field_center_circle_1', '2d:prop_soccer_goal', '2d:scool', '2d:scool_-', '2d:shop1', '2d:shop2', '2d:shop3', '2d:shop4', '2d:shop5', '2d:shop6', '2d:stadium_set', '2d:tile', '2d:tile_1', '2d:tile_2', '2d:tile_3', '2d:tile_4', '2d:tile_5', '2d:tile_6', '2d:tree128-192', '2d:tree96-160', '2d:wall', '2d:wall_-']

# index: (doorway x/y in its audit cell, outward ground axis).
# x means +X, z means +depth; base SW views mirror the SE doorway.
doors = {
    0:(66,232,'z'), 2:(66,232,'z'), 3:(102,230,'z'),
    5:(35,244,'z'), 7:(35,244,'z'), 10:(195,255,'x'), 12:(195,255,'x'),
    15:(48,241,'z'), 16:(146,225,'x'), 17:(163,235,'x'),
    18:(163,235,'x'), 19:(93,222,'z'),
    21:(165,217,'x'), 22:(166,227,'x'), 23:(158,188,'x'),
    24:(158,190,'x'), 25:(102,253,'z'), 26:(161,192,'x'),
    27:(158,188,'x'), 29:(158,188,'x'), 30:(158,188,'x'),
    31:(158,188,'x'), 32:(158,188,'x'), 33:(158,188,'x'),
    36:(128,265,'z'), 37:(119,252,'z'), 38:(83,223,'z'),
    39:(158,188,'x'), 40:(164,133,'z'), 41:(131,222,'z'),
    42:(107,238,'z'), 43:(169,192,'x'), 44:(169,192,'x'),
    45:(170,192,'x'), 46:(170,192,'x'), 47:(170,192,'x'),
    48:(170,192,'x'), 49:(158,188,'x'), 50:(157,244,'x'),
    51:(158,188,'x'), 52:(158,188,'x'), 53:(158,188,'x'),
    54:(102,224,'z'), 55:(110,211,'z'), 56:(141,224,'xz'),
    57:(139,203,'xz'), 58:(143,250,'x'), 59:(140,261,'z'),
    60:(110,255,'z'), 61:(116,267,'z'), 62:(98,269,'z'),
    63:(158,188,'x'), 64:(92,199,'z'), 65:(134,170,'z'),
    66:(158,188,'x'), 69:(193,237,'x'), 70:(195,242,'x'),
    71:(93,248,'z'), 72:(110,198,'z'), 73:(187,246,'x'),
    76:(178,207,'x'), 77:(187,223,'x'), 81:(122,247,'z'),
    82:(112,258,'z'), 83:(140,172,'z'), 104:(110,248,'z'),
    105:(137,204,'z'), 106:(106,257,'z'), 107:(106,257,'z'),
    108:(174,258,'x'), 109:(179,240,'x'), 110:(103,247,'z'),
    111:(103,247,'z'), 112:(167,209,'x'),
}

for i, asset in enumerate(ids):
    entry = behavior[asset]
    if i not in doors:
        entry['building'] = False
        entry['entrance'] = False
        continue
    entry['entrance'] = True
    x, y, axis = doors[i]
    data = items[asset[3:]]
    first = next(iter(data['directions'].values()))
    width, height = first['frame_width'], first['frame_height']
    # Match PIL thumbnail's integer dimensions and centering used by the audit.
    picture = Image.new('RGB', (width, height))
    picture.thumbnail((264, 255))
    raw = [(x - (280 - picture.width) // 2) * width / picture.width,
           (y - 30 - (255 - picture.height) // 2) * height / picture.height]
    views = {}
    for direction, view in data['directions'].items():
        pixel = list(raw)
        side = axis
        if direction == 'SW' and len(data['directions']) == 2:
            pixel[0] = view['frame_width'] - 1 - pixel[0]
            side = {'x': 'z', 'z': 'x', 'xz': 'xz'}[axis]
        origin = view['origin']
        px, py = pixel[0] - origin[0], pixel[1] - origin[1]
        a,b,c,d = view.get('alignment_transform', [1,0,0,1])
        px,py = a*px+c*py, b*px+d*py
        u,v = (px/16+py/8)/2, (py/8-px/16)/2
        foot = view['footprint']
        arrival = [u,v]
        if 'x' in side: arrival[0] = max(u + .7, foot[0] + .7)
        if 'z' in side: arrival[1] = max(v + .7, foot[1] + .7)
        views[direction] = {'point': [round(u,5),round(v,5)],
                            'arrival': [round(n,5) for n in arrival],
                            'source_pixel': [round(n,3) for n in pixel]}
    entry['entrance_anchor'] = {'views': views}

# Local model doorway thresholds and clear approaches, in source world units.
# Audited against the +X/+Z preview. All front elevations face +Z.
models = {
 'HanX_City/Apartment_4F_A':([-1.8,.02,4.05],[-1.8,.02,5.8]),
 'HanX_City/Apartment_4F_B':([-1.8,.02,4.05],[-1.8,.02,5.8]),
 'HanX_City/Apartment_6F_Balcony':([0,.02,4.05],[0,.02,4.8]),
 'HanX_City/Cafe_Small':([2.8,.02,3.05],[2.8,.02,4.9]),
 'HanX_City/Corner_Shop_Building':([0,.02,4.05],[0,.02,4.7]),
 'HanX_City/Historic_Building':([0,.02,4.05],[0,.02,4.5]),
 'HanX_City/Hotel':([0,.02,4.05],[0,.02,4.5]),
 'HanX_City/Metro_Entrance':([0,.02,2.5],[0,.02,4.5]),
 'HanX_City/Office_Tower':([0,.02,8.05],[0,.02,9.4]),
 'HanX_City/Parking_Garage':([-3,.02,5.05],[-3,.02,6.3]),
 'HanX_City/Row_Houses_A':([-1.7,.02,3.05],[-1.7,.02,4.5]),
 'HanX_City/Row_Houses_B':([-1.7,.02,3.05],[-1.7,.02,4.5]),
 'HanX_Construction/Building_Frame':([0,.02,4.05],[0,.02,5.2]),
 'HanX_GasStation/Car_Wash':([0,.02,4.5],[0,.02,5.5]),
 'HanX_GasStation/Gas_Station_Store':([3.6,.02,3.45],[3.6,.02,5.3]),
 'HanX_GasStation/Repair_Garage':([2.6,.02,3.45],[2.6,.02,5.3]),
 'HanX_Park/Gazebo':([0,.15,2.5],[0,.02,4.1]),
 'HanX_School/Gym_Building':([0,.02,6.55],[0,.02,7.9]),
 'HanX_School/Kindergarten_Building':([0,.02,3.7],[0,.02,5.1]),
 'HanX_School/School_Building':([0,.02,6.9],[0,.02,8.8]),
 'HanX_Shop/Shop_Bakery':([2.6,.02,3.05],[2.6,.02,4.5]),
 'HanX_Shop/Shop_Boutique':([2.6,.02,3.05],[2.6,.02,4.5]),
 'HanX_Shop/Shop_Butcher':([2.6,.02,3.05],[2.6,.02,4.5]),
 'HanX_Shop/Shop_Cafe':([2.6,.02,3.05],[2.6,.02,4.5]),
 'HanX_Shop/Shop_Florist':([2.6,.02,3.05],[2.6,.02,4.5]),
 'HanX_Shop/Shop_Grocery':([2.6,.02,3.05],[2.6,.02,4.5]),
 'HanX_Shop/Shop_Ice_Cream':([2.6,.02,3.05],[2.6,.02,4.5]),
 'HanX_Shop/Shop_Pharmacy':([2.6,.02,3.05],[2.6,.02,4.5]),
}
for asset, entry in behavior.items():
    if asset.startswith('3d:') and entry.get('building') and asset[3:] not in models:
        entry['building'] = False
        entry['entrance'] = False
for name, (point, arrival) in models.items():
    entry = behavior['3d:' + name]
    entry.update(building=True, entrance=True, layer='Buildings', collision='mesh',
                 entrance_anchor={'point':point,'arrival':arrival})

(CAT / 'asset_behaviors.json').write_text(json.dumps(behavior, indent='\t',sort_keys=True)+'\n')
print(f'Authored {len(doors)} sprite buildings and {len(models)} model buildings.')
