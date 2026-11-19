# Clock catalyst — model review 02

2026-11-18. Floating blue-white clock catalyst, with restrained gold meridians;
same broad anime colour treatment as the wing sword. No handle or pedestal.

## Structure

- Three circles share the same centre and horizontal **X diameter line**.
  Their radii are 0.238 / 0.224 / 0.210 m to provide physical rotational clearance.
  They do not have literally identical radius/endpoints, which would intersect.
- Rest tilts around X: 0° / +65° / −65°. The result has spherical depth.
- All three rings move: outer +1, middle −1, inner +2 turns per 8 seconds.
- Unsupported blue-white projected Roman dial, 0.302 m diameter, turns once per
  8 seconds around its vertical Z axis. This retains its prior independent spin.
- No north/south rods, collars, caps, clock edge, or opaque backing disk.
- Projection uses alpha-blended emissive materials: faint cyan field and scanlines,
  white-blue numerals/ticks, reverse-time arrows, interrupted light perimeter.
  It is one two-sided light surface; its back naturally shows mirrored graphics.
- Blender Z-up; GLB Y-up; metres. Origin is the common centre. Outer diameter 0.485 m.
- The larger surrounding gauzy stellar veil remains deferred.

## Deliverables

`out/clock_catalyst_v2/clock_catalyst.blend` — editable scene, independent controllers.
`out/clock_catalyst_v2/clock_catalyst.glb` — four mesh nodes, one synchronized clip.
`out/clock_catalyst_v2/model_sheet.jpg` — actual rendered front/side/top and hero.
`out/clock_catalyst_v2/rotation.gif` — actual model animation, 80 frames / 8 seconds.

Version 1 deliverables remain in `out/clock_catalyst/`, with their generator
snapshots under `generator_v1/`. Version 2 does not overwrite those artifacts.

The Mivo Tripo source is retained in `out/clock_catalyst/source/`. It interpreted
the three-view reference as three fused props and produced ~1.40M triangles.
Its topology is not used in the delivered model; the same design was manually
rebuilt with clean ring/dial geometry for exact pivots and independent rotation.
This is a review model, not yet connected to the game or optimized as final LOD.

## Reproduce

Run from project root using the installed Blender binary:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 -P art/weapon_gen/clock_catalyst_blender.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 -P art/weapon_gen/clock_catalyst_verify.py
python3 art/weapon_gen/clock_catalyst_present.py
```

Full logs under `out/clock_catalyst_v2/logs/`; numeric inspection in
`model-report.json` and independent GLB import checks in `roundtrip-report.json`.
