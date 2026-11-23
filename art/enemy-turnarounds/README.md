# Enemy voxel turnarounds

These PNGs are generated offline from the Lua `Build()` tables. The renderer evaluates each model with Lua 5.4 through Lupa, validates the shared cell contract, enumerates exposed faces, and shades every face from its palette RGB, roughness, metallic, and emission values. No UrhoX world, Spawner, remote build, or network service is started.

Run the complete candidate set from the project root. Missing candidates are skipped so the same command remains valid as models arrive.

```sh
python3 art/enemy-turnarounds/render_enemy_models.py --all
```

Render one model when iterating.

```sh
python3 art/enemy-turnarounds/render_enemy_models.py --model RuinConstruct
python3 art/enemy-turnarounds/render_enemy_models.py --model TimeWraith
```

The four-view sheet contains front, right, back, and three-quarter views. The lighting sheet compares the day key light with a cool rim key light. The command prints the measured solid-cell count, unique root-cell count, and part count.

Framing uses one orthographic scale across all four views. It fits the complete voxel envelope into the rectangle below the 58 px title bar, keeps a 16 px top margin, and places every view on the same ground line. The front camera uses the authoring hand so root-space +X appears on the left of the image.

Measured on 2026-11-24

| model | solid cells | unique root cells | parts |
| --- | ---: | ---: | ---: |
| RuinConstruct | 1958 | 1958 | 9 |
| TimeWraith | 2023 | 2023 | 13 |
| WoodSpirit | 1895 | 1895 | 8 |
| NestWeaver | 1920 | 1920 | 15 |
| RockColossus | 2984 | 2984 | 9 |

The script validates integer coordinates, palette references, duplicate cells, six-colour maximum, and the 3000-cell limit before writing an image.
