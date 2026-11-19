# Clock catalyst — model review 01

2026-11-18. Floating blue-white clock catalyst, with restrained gold meridians;
same broad anime colour treatment as the wing sword. No handle or pedestal.

## Structure

- Three upright circles share the same centre and vertical **diameter line**.
  Their radii are 0.238 / 0.224 / 0.210 m to provide physical rotational clearance.
  They do not have literally identical radius/endpoints, which would intersect.
- Rest azimuths: 0° / +65° / −65°. The result has depth, not a stack of flat rings.
- Outer meridian fixed; middle and inner rotate in opposite directions.
- White/cobalt double-sided Roman dial, 0.302 m diameter, rotates as a whole
  around the same vertical axis. Reverse-time icon on both faces.
- Short axial stems and collars connect the poles. No bar crosses the dial face.
- Blender Z-up; GLB Y-up; metres. Origin is the common centre. Height 0.516 m.
- Blue-white gauzy stars/veil are deferred; the model contains only solid parts.

## Deliverables

`out/clock_catalyst/clock_catalyst.blend` — editable scene, independent controllers.
`out/clock_catalyst/clock_catalyst.glb` — five mesh nodes, unlit palette, animation.
`out/clock_catalyst/model_sheet.jpg` — actual rendered front/side/top and hero.
`out/clock_catalyst/rotation.gif` — actual animated model, 8-second loop.

The Mivo Tripo source is retained in `out/clock_catalyst/source/`. It interpreted
the three-view reference as three fused props and produced ~1.40M triangles.
Its topology is not used in the delivered model; the same design was manually
rebuilt with clean ring/dial geometry for exact pivots and independent rotation.
This is a review model, not yet connected to the game or optimized as final LOD.

## Reproduce

Run from project root using the installed Blender binary:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P art/weapon_gen/clock_catalyst_blender.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P art/weapon_gen/clock_catalyst_verify.py
python3 art/weapon_gen/clock_catalyst_present.py
```

Full logs under `out/clock_catalyst/logs/`; numeric inspection in
`model-report.json` and independent GLB import checks in `roundtrip-report.json`.
