#!/usr/bin/env python3
"""Import Nomi's BB rest pose without the Bedrock export's mirrored X axis.

Usage: python3 art/nomi_ysm/import_bbmodel.py /path/to/诺米.bbmodel
The runtime reflects Z and composes BB's ZYX rotations. Keep every cube's
unrotated bounds, own origin/rotation, face UVs and the full group hierarchy.
"""
import argparse
import json
import math
from pathlib import Path


ALIASES = {
    "Root": "root", "UpBody": "body", "Head": "head",
    "Hair": "hair_locks", "LongHair": "hair_back",
    "LeftArm": "arm_left", "RightArm": "arm_right",
    "LeftForeArm": "forearm_left", "RightForeArm": "forearm_right",
    "LeftLeg": "leg_left", "RightLeg": "leg_right",
    "LeftLowerLeg": "ysm_LeftLowerLeg", "LeftFoot": "ysm_LeftFoot",
    "RightLowerLeg": "ysm_RightLowerLeg", "RightFoot": "ysm_RightFoot",
    "NomiWaistFollow": "skirt", "NomiOvercoat": "coat_upper",
    "NomiCoatLeft": "coat_lower", "NomiCoatRight": "ysm_NomiCoatRight",
    "NomiHood": "hood",
}


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, dict):
        return "{" + ",".join(k + "=" + lua(v) for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(lua(v) for v in value) + "}"
    return json.dumps(value, ensure_ascii=False, allow_nan=False)


def animation_data(source):
    """Keep authored local channels, including every cloth/hair bone.

    Fail on unfamiliar interpolation/expressions rather than silently dropping
    channels. The only Molang dependency is the run root's head-yaw roll.
    """
    groups = {g["uuid"]: g for g in source["groups"]}
    result = {}
    for anim in source["animations"]:
        if anim["name"] not in ("idle", "walk", "run"):
            continue
        assert anim["loop"] == "loop" and not anim.get("override")
        tracks = {}
        for uuid, animator in anim["animators"].items():
            frames = animator.get("keyframes", [])
            if not frames:
                continue
            assert uuid in groups, animator.get("name")
            assert not animator.get("rotation_global")
            assert not animator.get("quaternion_interpolation")
            name = groups[uuid]["name"]
            channels = {}
            for frame in frames:
                channel = frame["channel"]
                assert channel in ("rotation", "position", "scale")
                assert frame.get("interpolation", "linear") == "linear"
                assert len(frame["data_points"]) == 1
                values = []
                for axis in "xyz":
                    value = frame["data_points"][0][axis]
                    if value == "0.4*ysm.head_yaw":
                        value = {"headYaw": 0.4}
                    else:
                        value = float(value)
                        assert math.isfinite(value)
                    values.append(value)
                channels.setdefault(channel, []).append([frame["time"], *values])
            for frames in channels.values():
                frames.sort(key=lambda f: f[0])
                assert all(a[0] < b[0] for a, b in zip(frames, frames[1:]))
            tracks[ALIASES.get(name, name)] = channels
        result[anim["name"]] = dict(length=anim["length"], tracks=tracks)
    assert set(result) == {"idle", "walk", "run"}
    return result


def convert(source):
    groups = {g["uuid"]: g for g in source["groups"]}
    elements = {e["uuid"]: e for e in source["elements"]}
    bones, owners = [], {}

    def visit(entry, parent=None):
        if isinstance(entry, str):
            assert entry in elements and parent is not None, entry
            owners[entry] = parent
            return
        group = groups[entry["uuid"]]
        name = ALIASES.get(group["name"], group["name"])
        bones.append(dict(name=name, sourceName=group["name"], parent=parent,
                          pivot=group["origin"], rotation=group.get("rotation", [0, 0, 0])))
        for child in entry.get("children", []):
            visit(child, name)

    for entry in source["outliner"]:
        visit(entry)
    assert len(bones) == len(groups)
    assert len({b["name"] for b in bones}) == len(bones), "Duplicate bone alias"
    cubes = []
    for element in source["elements"]:
        assert element["type"] == "cube"
        assert element.get("stretch", [1, 1, 1]) == [1, 1, 1]
        assert not element.get("rescale", False)
        assert element.get("visibility", True) and element.get("export", True)
        faces = element["faces"]
        assert all(f.get("texture") == 0 for f in faces.values()), "Expected original atlas"
        cube = dict(bone=owners[element["uuid"]], uuid=element["uuid"],
                    **{"from": element["from"]},
                    size=[b - a for a, b in zip(element["from"], element["to"])],
                    origin=element["origin"], rotation=element.get("rotation", [0, 0, 0]),
                    inflate=element.get("inflate", 0),
                    uv={face: value["uv"] for face, value in faces.items()})
        rotations = {face: value["rotation"] for face, value in faces.items()
                     if value.get("rotation", 0)}
        if rotations:
            assert all(v in (90, 180, 270) for v in rotations.values())
            cube["uvRotation"] = rotations
        cubes.append(cube)
    resolution = source["resolution"]
    return ("-- Generated from 诺米.bbmodel by art/nomi_ysm/import_bbmodel.py.\n"
            "-- Original BB coordinates and ZYX bind/cube rotations; runtime reflects Z.\n"
            'return {texture="Textures/Characters/nomi.png",'
            f'uvWidth={resolution["width"]},uvHeight={resolution["height"]},bones={{\n'
            + "".join(" " + lua(b) + ",\n" for b in bones) + "},cubes={\n"
            + "".join(" " + lua(c) + ",\n" for c in cubes)
            + "},animations=" + lua(animation_data(source)) + "}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bbmodel", type=Path)
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[2] / "scripts/game/NomiYSMData.lua")
    args = parser.parse_args()
    args.output.write_text(convert(json.loads(args.bbmodel.read_text())), encoding="utf-8")
    print(args.output)


if __name__ == "__main__":
    main()
