import struct

def parse_vox(path):
    data = open(path, 'rb').read()
    i = 20
    voxels, palette = [], None
    while i < len(data):
        cid = data[i:i+4]
        n, m = struct.unpack('<ii', data[i+4:i+12])
        body = data[i+12:i+12+n]
        if cid == b'XYZI' and not voxels:
            cnt = struct.unpack('<i', body[:4])[0]
            for k in range(cnt):
                voxels.append(struct.unpack('<BBBB', body[4+k*4:8+k*4]))
        elif cid == b'RGBA':
            palette = [struct.unpack('<BBBB', body[k*4:k*4+4]) for k in range(256)]
        i += 12 + n
    return voxels, palette

for name in ['obj_stlight1', 'obj_stlight2', 'obj_stlight3']:
    voxels, pal = parse_vox(name + '.vox')
    bright = []
    for (x, y, z, c) in voxels:
        r, g, b, a = pal[c-1]
        if r + g + b > 500 and r > b:
            bright.append((x, y, z))
    clusters = []
    for v in bright:
        placed = False
        for cl in clusters:
            cx, cy, cz = cl['sx']/cl['n'], cl['sy']/cl['n'], cl['sz']/cl['n']
            if (v[0]-cx)**2 + (v[1]-cy)**2 + (v[2]-cz)**2 <= 36:
                cl['sx'] += v[0]; cl['sy'] += v[1]; cl['sz'] += v[2]; cl['n'] += 1
                placed = True
                break
        if not placed:
            clusters.append({'sx': v[0], 'sy': v[1], 'sz': v[2], 'n': 1})
    print('==', name)
    for cl in clusters:
        cx, cy, cz = cl['sx']/cl['n'], cl['sy']/cl['n'], cl['sz']/cl['n']
        print('   n=%d ENGINE voxel center (%.1f, %.1f, %.1f)' % (cl['n'], cx + 0.5, cz + 0.5, cy + 0.5))
