#!/usr/bin/env python3
"""Deterministic landmark trace of the approved 3840x2160 three-view.
Landmarks are image pixels, NOT fitted to the previous mesh. Feather boundaries
are hand traced: gold regions touch across highlights, so colour connected
components cannot reliably separate feathers. The PNG alpha/colour masks are
used independently by compare_wingsword.py, not copied from these polygons.
Run with python3 -I; standard library only.
"""
import json, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = 'art/weapons_2d/sword_wing_long_threeview_v1.png'
TIP_PIXEL, BOTTOM_PIXEL, CENTER_X = 50, 2035, 949
SCALE = 1.855 / (BOTTOM_PIXEL - TIP_PIXEL)
def xy(p):
    return [(p[0]-CENTER_X)*SCALE, 1.62-(p[1]-TIP_PIXEL)*SCALE]

# Ordered outline landmarks, back-to-front layer order. Sharp straight leading
# edges, concave trailing shoulders; front and rear share the mirrored silhouette.
FEATHERS = [
 ('L_top', [(681,1198),(881,1361),(883,1390),(935,1476),(823,1395),(721,1318)], (855,1377)),
 ('L_upper', [(738,1349),(883,1401),(938,1482),(831,1432),(778,1405)], (859,1420)),
 ('L_middle', [(696,1390),(815,1413),(939,1472),(837,1476),(762,1448)], (845,1450)),
 ('L_small', [(800,1491),(850,1454),(937,1462),(905,1483),(853,1492)], (869,1474)),
 ('L_lower', [(800,1580),(847,1497),(936,1450),(930,1494),(903,1516),(882,1546)], (872,1515)),
 ('R_top', [(1218,1288),(1152,1393),(1032,1439),(970,1484),(988,1412),(1021,1382)], (1065,1411)),
 ('R_middle', [(1148,1443),(1088,1478),(1009,1476),(968,1490),(1024,1444),(1106,1420)], (1053,1449)),
 ('R_lower', [(1104,1540),(1041,1519),(1007,1482),(974,1482),(1006,1461),(1073,1484)], (1019,1473)),
]
# Station widths measured against alpha>128 in the blade-only crop. Root
# concavities are landmark traces where feathers occlude the blade boundary.
# y pixel, left x, right x, core half-width / outer half-width, side half-depth px
BLADE = [
 (1443,911,987,.48,28), (1400,871,1027,.48,29),
 (1360,887,1011,.48,29), (1320,877,1021,.49,29),
 (1290,853,1045,.51,29), 
 (1150,876,1022,.48,29),
 (800,883,1015,.44,30),
 (350,875,1025,.22,32),
 (180,918,982,.035,15),
]
CORE = [(949,1409),(981,1451),(991,1480),(977,1510),(977,1536),
        (1001,1561),(980,1594),(984,1614),(970,1640),(945,1708),
        (921,1641),(910,1615),(920,1591),(895,1562),(918,1534),
        (916,1511),(904,1484),(925,1447)]
# Side-view measured outer envelope at y~350 and guard y~1450.
SIDE = {'blade_max_px': 70, 'guard_max_px': 138, 'source_axis_x': 1925}
TRACE = dict(source=SOURCE, tip_pixel=TIP_PIXEL,bottom_pixel=BOTTOM_PIXEL,
             center_x=CENTER_X, scale=SCALE, feathers=FEATHERS,blade=BLADE,
             guard_core=CORE, side=SIDE)
if __name__ == '__main__':
    out=ROOT/'art/weapon_gen/out/wingsword_trace.json'
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(TRACE,indent=2)+'\n')
    print(out)
