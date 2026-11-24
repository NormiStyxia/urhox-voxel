# Enemy role samples (current reviewer sample)

- `role_samples_current.png`: top-down telegraph/active/recover geometry for the five actors, hurt-shape circles and timing bars.
- `role_samples_current.json`: exact sampled transforms, warning kinds, hurt shapes, thread/beam/field flags.

Environment: Python 3 + Lupa Lua 5.4 + Pillow; no UrhoX Runtime, physics world, remote build or game frame. Mock scene/world only constructs real actors/effect nodes. TimeWraith field scale is source-wired to Nomi run/gravity and CombatMoves attack/draw clocks; this sample is geometry-only, not a dynamic frame. Re-run: `python3 tests/combat/actor_role_samples.py` from `/private/tmp/ruins-enemy-roles`.
