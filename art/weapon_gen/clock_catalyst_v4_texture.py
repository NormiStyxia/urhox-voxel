"""Bake seamless blue-white cloud colour and a soft stellar dust sprite."""
from pathlib import Path
import numpy as np
from PIL import Image

output = Path('art/weapon_gen/out/clock_catalyst_v4')
output.mkdir(parents=True, exist_ok=True)
width, height = 1024, 512
longitude, latitude = np.meshgrid(np.linspace(0, 2*np.pi, width), np.linspace(-np.pi/2, np.pi/2, height))
x = np.cos(latitude)*np.cos(longitude)
y = np.cos(latitude)*np.sin(longitude)
z = np.sin(latitude)
warp = 2.2*np.sin(2*x + 3*z) + 1.3*np.cos(3*y - z)
cloud = (.46 + .23*np.sin(5*x + 3*y + warp)
         + .13*np.sin(8*z - 4*y + warp)
         + .07*np.cos(16*x + 9*y - 7*z)
         + .035*np.sin(28*z + 18*y))
cloud = np.clip(cloud, 0, 1)
stops = np.array([0, .26, .43, .56, .68, .84, 1])
colours = np.array([[15,43,110],[29,81,172],[64,140,223],[133,197,244],
                    [211,237,253],[244,252,255],[255,255,255]])
pixels = np.stack([np.interp(cloud, stops, colours[:,c]) for c in range(3)], axis=-1)
# A few small stars are fixed to the sphere surface, not another opaque shell.
rng = np.random.default_rng(42)
for unused in range(64):
    direction = rng.normal(size=3)
    direction /= np.linalg.norm(direction)
    distance_squared = np.maximum(0, 2*(1 - x*direction[0] - y*direction[1] - z*direction[2]))
    intensity = np.exp(-distance_squared/rng.uniform(.000015, .00006))*.8
    pixels = pixels*(1-intensity[...,None]) + np.array([221,244,255])*intensity[...,None]
Image.fromarray(np.uint8(np.clip(pixels,0,255))).save(output/'core_blue_white.png')
grid_y, grid_x = np.mgrid[-1:1:128j,-1:1:128j]
distance = grid_x**2+grid_y**2
sprite = np.zeros((128,128,4),dtype=np.uint8)
sprite[:,:,:3] = [80,161,255]
sprite[:,:,3] = np.uint8(16*np.exp(-distance*6)*np.clip(1-distance,0,1))
Image.fromarray(sprite).save(output/'stardust_haze.png')
print('PASS texture preparation: seamless sphere colour and feathered haze alpha')
