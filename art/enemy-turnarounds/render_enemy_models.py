#!/usr/bin/env python3
"""Offline four-view renderer for the shared enemy Build() voxel contract.

The renderer evaluates the real Lua model with Lupa, then shades exposed voxel
faces from the model RGB/roughness/metallic/emission entries. It never imports
UrhoX or creates a physics world, so it can be run from a clean checkout.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "scripts" / "combat" / "enemies" / "models"
CANDIDATES = ["RuinConstruct", "TimeWraith", "WoodSpirit", "NestWeaver", "RockColossus"]
OUT_DIR = Path(__file__).resolve().parent

VIEWS = {
    "front": (0.0, 1.2, 8.0),
    "right": (8.0, 1.2, 0.0),
    "back": (0.0, 1.2, -8.0),
    "threequarter": (6.2, 1.6, 6.2),
}
LIGHTS = {
    "day": ((-0.55, 0.82, 0.42), (0.18, 0.20, 0.24)),
    "rim": ((0.42, 0.56, -0.72), (0.10, 0.14, 0.22)),
}
TITLE_HEIGHT = 58
TOP_MARGIN = 16
GROUND_FRACTION = 0.82


def lua_to_python(value):
    if hasattr(value, "items"):
        items = list(value.items())
        integer_keys = [k for k, _ in items if isinstance(k, (int, float)) and int(k) == k]
        if integer_keys and min(integer_keys) == 1 and max(integer_keys) == len(integer_keys):
            return [lua_to_python(value[i]) for i in range(1, len(integer_keys) + 1)]
        return {k: lua_to_python(v) for k, v in items}
    return value


def load_model(name: str):
    path = MODEL_DIR / f"{name}.lua"
    if not path.exists():
        return None
    lua = LuaRuntime(unpack_returned_tuples=True)
    module = lua.eval("dofile")(str(path))
    built = module["Build"]()
    return lua_to_python(built)


def validate(name: str, model: dict):
    errors = []
    size = model.get("size")
    palette = model.get("palette", [])
    parts = model.get("parts", [])
    if not isinstance(size, (int, float)) or size <= 0:
        errors.append("size must be positive")
    if len(palette) > 6:
        errors.append(f"palette has {len(palette)} entries, limit is 6")
    for i, entry in enumerate(palette, 1):
        rgb = entry.get("rgb", [])
        if len(rgb) != 3 or any(not isinstance(v, (int, float)) or not 0 <= v <= 255 for v in rgb):
            errors.append(f"palette[{i}] has invalid RGB")
        for field in ("roughness", "metallic", "emission"):
            value = entry.get(field, 0)
            if not isinstance(value, (int, float)) or value < 0:
                errors.append(f"palette[{i}].{field} is invalid")
    all_cells = set()
    total = 0
    for part in parts:
        local = set()
        for cell in part.get("cells", []):
            if len(cell) != 4 or any(not isinstance(v, (int, float)) or int(v) != v for v in cell[:3]):
                errors.append(f"{part.get('id', '?')} has a non-integer cell")
                continue
            xyz = tuple(int(v) for v in cell[:3])
            material = cell[3]
            if not 1 <= material <= len(palette):
                errors.append(f"{part.get('id', '?')} references palette {material}")
            if xyz in local:
                errors.append(f"{part.get('id', '?')} repeats cell {xyz}")
            local.add(xyz)
            if xyz in all_cells:
                errors.append(f"duplicate root cell {xyz}")
            all_cells.add(xyz)
            total += 1
        pivot = part.get("pivot", [])
        if len(pivot) != 3 or any(not isinstance(v, (int, float)) for v in pivot):
            errors.append(f"{part.get('id', '?')} has invalid pivot")
    if total > 3000:
        errors.append(f"{total} solid cells exceeds 3000")
    if errors:
        raise ValueError(f"{name}: " + "; ".join(errors))
    return total, len(all_cells), len(parts)


def normalize(v):
    length = math.sqrt(sum(x * x for x in v)) or 1.0
    return tuple(x / length for x in v)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def mul(a, n):
    return tuple(x * n for x in a)


def shade(rgb, roughness, metallic, emission, normal, light, ambient, view_dir):
    # A compact PBR-inspired directional model. Roughness narrows the specular
    # lobe, metallic tints it with the base colour, and emission remains visible
    # in the shadowed views.
    n = normalize(normal)
    l = normalize(light)
    view = normalize(tuple(-v for v in view_dir))
    half_vec = normalize(add(l, view))
    diffuse = max(0.0, dot(n, l))
    shininess = 4.0 + (1.0 - min(1.0, roughness)) * 80.0
    spec = max(0.0, dot(n, half_vec)) ** shininess
    base = tuple(c / 255.0 for c in rgb)
    result = []
    for channel, c in enumerate(base):
        env = ambient[channel] * (0.45 + 0.55 * (1.0 - min(1.0, roughness)))
        reflected = (diffuse * 0.80 + env) * c
        reflected += metallic * (spec * c * 0.9 + env * c * 0.35)
        reflected += (1.0 - metallic) * spec * 0.20
        result.append(max(0.0, min(1.0, reflected + c * emission * 0.55)))
    # Mild display transfer keeps stone readable while retaining emissive peaks.
    return tuple(int(round((v ** (1.0 / 2.2)) * 255)) for v in result)


def face_geometry(cell, normal, size):
    cx, cy, cz = ((cell[i] + 0.5) * size for i in range(3))
    h = size * 0.5
    axis = max(range(3), key=lambda i: abs(normal[i]))
    fixed = (cx, cy, cz)
    corners = []
    for first, second in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        p = [fixed[0], fixed[1], fixed[2]]
        p[axis] += h * (1 if normal[axis] > 0 else -1)
        free = [i for i in range(3) if i != axis]
        p[free[0]] += h * first
        p[free[1]] += h * second
        corners.append(tuple(p))
    return corners


def frame_scale(model: dict, width: int, height: int) -> float:
    """Fit one scale to all views and the rectangle below the title."""
    size = float(model["size"])
    coords = [tuple(int(v) for v in cell[:3]) for part in model["parts"] for cell in part["cells"]]
    center_cells = tuple((min(c[i] for c in coords) + max(c[i] for c in coords) + 1) * 0.5 for i in range(3))
    target = tuple(v * size for v in center_cells)
    max_horizontal = max_top = max_bottom = 1e-6
    for view_pos in VIEWS.values():
        view_dir = normalize(tuple(target[i] - view_pos[i] for i in range(3)))
        right = normalize(cross((0.0, 1.0, 0.0), view_dir))
        up = normalize(cross(view_dir, right))
        ground = (target[0], 0.0, target[2])
        for xyz in coords:
            center = tuple((xyz[i] + 0.5) * size for i in range(3))
            rel_target = tuple(center[i] - target[i] for i in range(3))
            rel_ground = tuple(center[i] - ground[i] for i in range(3))
            max_horizontal = max(max_horizontal, abs(dot(rel_target, right)) + size * 0.5 * sum(abs(v) for v in right))
            up_extent = dot(rel_ground, up)
            support = size * 0.5 * sum(abs(v) for v in up)
            max_top = max(max_top, up_extent + support)
            max_bottom = max(max_bottom, -(up_extent - support))
    ground_y = height * GROUND_FRACTION
    available_top = max(1.0, ground_y - TITLE_HEIGHT - TOP_MARGIN)
    available_bottom = max(1.0, height - ground_y - 8.0)
    return min(width * 0.43 / max_horizontal, available_top / max_top, available_bottom / max_bottom)


def render(model: dict, view_pos, light, ambient, width=680, height=680, scale=None):
    size = float(model["size"])
    entries = model["palette"]
    occupancy = {}
    coords = []
    for part in model["parts"]:
        for cell in part["cells"]:
            xyz = tuple(int(v) for v in cell[:3])
            occupancy.setdefault(xyz, int(cell[3]))
            coords.append(xyz)
    center_cells = tuple((min(c[i] for c in coords) + max(c[i] for c in coords) + 1) * 0.5 for i in range(3))
    center = tuple(v * size for v in center_cells)
    target = center
    view_dir = normalize(tuple(target[i] - view_pos[i] for i in range(3)))
    right = normalize(cross((0.0, 1.0, 0.0), view_dir))
    up = normalize(cross(view_dir, right))
    faces = []
    normals = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
    for xyz, palette_index in occupancy.items():
        for normal in normals:
            neighbor = tuple(xyz[i] + normal[i] for i in range(3))
            if neighbor in occupancy:
                continue
            points = face_geometry(xyz, normal, size)
            projected = []
            for point in points:
                rel = tuple(point[i] - target[i] for i in range(3))
                projected.append((dot(rel, right), dot(rel, up)))
            depth = sum(dot(tuple(point[i] - target[i] for i in range(3)), view_dir) for point in points) / 4.0
            entry = entries[palette_index - 1]
            color = shade(entry["rgb"], float(entry.get("roughness", 0.85)), float(entry.get("metallic", 0)), float(entry.get("emission", 0)), normal, light, ambient, view_dir)
            faces.append((depth, projected, color))
    scale = scale or frame_scale(model, width, height)
    image = Image.new("RGB", (width, height), (22, 25, 31))
    draw = ImageDraw.Draw(image)
    ground_ref = (target[0], 0.0, target[2])
    ground_y = int(height * GROUND_FRACTION)
    ground_level = dot(tuple(ground_ref[i] - target[i] for i in range(3)), up)
    horizon = ground_y
    draw.line((0, horizon, width, horizon), fill=(48, 52, 62), width=2)
    scaled_faces = []
    for depth, polygon, color in faces:
        scaled = [(width * 0.5 + x * scale, ground_y - (y - ground_level) * scale) for x, y in polygon]
        scaled_faces.append((depth, scaled, color))
    for _, polygon, color in sorted(scaled_faces, key=lambda item: item[0], reverse=True):
        draw.polygon(polygon, fill=color)
    return image


def label(image, title, subtitle):
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, image.width, 58), fill=(14, 17, 22))
    draw.text((16, 12), title, fill=(236, 239, 242))
    draw.text((16, 34), subtitle, fill=(166, 178, 190))
    return image


def make_sheet(name, model, metrics):
    total, unique, part_count = metrics
    common_scale = frame_scale(model, 680, 680)
    cards = []
    for view, position in VIEWS.items():
        card = render(model, position, LIGHTS["day"][0], LIGHTS["day"][1], scale=common_scale)
        cards.append(label(card, view, f"{total} cells  |  {part_count} parts"))
    sheet = Image.new("RGB", (1360, 1360), (10, 12, 16))
    for i, card in enumerate(cards):
        sheet.paste(card.resize((680, 680)), ((i % 2) * 680, (i // 2) * 680))
    sheet.save(OUT_DIR / f"{name}_turnaround.png")

    variants = []
    for light_name, (direction, ambient) in LIGHTS.items():
        card = render(model, VIEWS["threequarter"], direction, ambient, scale=common_scale)
        variants.append(label(card, light_name, f"threequarter | {total} cells"))
    lighting = Image.new("RGB", (1360, 680), (10, 12, 16))
    lighting.paste(variants[0], (0, 0))
    lighting.paste(variants[1], (680, 0))
    lighting.save(OUT_DIR / f"{name}_lighting.png")


def main():
    parser = argparse.ArgumentParser(description="Render enemy Build() models offline")
    parser.add_argument("--model", action="append", help="model basename, repeatable")
    parser.add_argument("--all", action="store_true", help="render all five candidate names that exist")
    args = parser.parse_args()
    names = args.model or (CANDIDATES if args.all or not args.model else [])
    found = []
    for name in names:
        model = load_model(name)
        if model is None:
            print(f"SKIP {name}: model file is not present")
            continue
        metrics = validate(name, model)
        make_sheet(name, model, metrics)
        print(f"OK {name}: cells={metrics[0]} unique={metrics[1]} parts={metrics[2]} outputs={OUT_DIR}")
        found.append(name)
    if not found:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
