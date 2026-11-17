"""Blender thornbow_game.json -> packed runtime JSON (never generated Lua code).

Usage: python3 art/weapon_gen/thornbow_export.py [input.json] [output.json]
Positions: 1e-4 m; normals: 1e-3; material weights/alpha/glow: 1e-2.
Vertex layout and coordinate conventions are documented in README-thornbow.md.
"""
import argparse
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INPUT = ROOT / "art/weapon_gen/out/thornbow_game.json"
DEFAULT_OUTPUT = ROOT / "assets/model/forge-blades/ThornBow.mesh.json"
PARTS = ("body", "crystal", "string")   # opaque mesh, translucent crystal pass, bow string


def orient(rows):
    # Blender->game reflects an axis. Preserve outward winding relative to normals.
    out = []
    for i in range(0, len(rows), 3):
        a, b, c = rows[i:i + 3]
        pa, pb, pc = np.array(a[:3]), np.array(b[:3]), np.array(c[:3])
        n = np.array(a[3:6]) + np.array(b[3:6]) + np.array(c[3:6])
        if np.dot(np.cross(pb - pa, pc - pa), n) < 0:
            b, c = c, b
        out.extend((a, b, c))
    return out


def pack(rows):
    table, verts, indices = {}, [], []
    for row in orient(rows):
        key = tuple(round(value * scale) for value, scale in
                    zip(row, (10000,) * 3 + (1000,) * 3 + (100,) * 5))
        if key not in table:
            table[key] = len(verts) + 1
            verts.append(key)
        indices.append(table[key])
    return {"triangles": len(indices) // 3,
            "v": [value for vertex in verts for value in vertex], "i": indices}


def build(data):
    for name in PARTS:
        rows = data["parts"][name]
        if not rows or len(rows) % 3 or any(len(row) != 11 for row in rows):
            raise ValueError(f"{name}: expected triangle vertices with 11 components")
        if not np.isfinite(np.array(rows)).all():
            raise ValueError(f"{name}: non-finite vertex component")
    allv = np.array([row for name in PARTS for row in data["parts"][name]])
    mn, mx = allv[:, :3].min(0), allv[:, :3].max(0)
    sv = np.array(data["parts"]["string"])
    crystal = np.array(data["parts"]["crystal"])
    # Keep the previous Lua export's exact four-decimal metadata rounding.
    def q(value):
        return float(f"{value:.4f}")
    return {
        "formatVersion": 1, "vertexStride": 11,
        "name": "thorn_bow", "scale": 10000, "nscale": 1000,
        "height": q(mx[1] - mn[1]),
        "bounds": {"min": list(map(q, mn)), "max": list(map(q, mx))},
        "sockets": {"grip": [0, 0, 0], "top": [0, q(mx[1]), 0],
                    "bottom": [0, q(mn[1]), 0], "stringZ": q(sv[:, 2].mean()),
                    "crystalTip": q(crystal[:, 2].max())},
        **{name: pack(data["parts"][name]) for name in PARTS},
    }


def encode(model):
    # One vertex / five triangles per line: inspectable data, deterministic diffs.
    header = {key: value for key, value in model.items() if key not in PARTS}
    lines = [json.dumps(header, indent=2)[:-2] + ","]
    for part_index, name in enumerate(PARTS):
        part = model[name]
        lines.append(f'  "{name}": {{"triangles": {part["triangles"]},')
        for key, width in (("v", 11), ("i", 15)):
            lines.append(f'    "{key}": [')
            values = part[key]
            for start in range(0, len(values), width):
                row = ",".join(map(str, values[start:start + width]))
                lines.append("      " + row + ("," if start + width < len(values) else ""))
            lines.append("    ]" + ("," if key == "v" else ""))
        lines.append("  }" + ("," if part_index < len(PARTS) - 1 else ""))
    return "\n".join(lines + ["}", ""])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("output", nargs="?", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    if args.output.suffix != ".json":
        parser.error("output must be .json; ThornBow.lua is now a hand-maintained loader")
    model = build(json.loads(args.input.read_text()))
    encoded = encode(model)
    assert json.loads(encoded) == model
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(encoded)
    print(f'wrote {args.output}: ' + ", ".join(f'{name}={model[name]["triangles"]}' for name in PARTS) + " triangles")


if __name__ == "__main__":
    main()
