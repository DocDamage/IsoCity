# Asset expansion fixtures

The six golden scenarios use the version 1 envelope defined by [golden.schema.json](golden.schema.json). The scenario name matches its filename. All six use seed 42. Placed objects use explicit IDs, and the modern block records the seed in its resident and service settings. Studio validates the nested document and its installed assets through the current document and repair routines.

| Fixture | Authored case |
| --- | --- |
| `modern_block.json` | Homes, café, grocery, school and bus, gas station, signalized junction and fire response route |
| `interior_activity_floor.json` | Classroom seats, counter, laundry, kitchen and elevator to a second floor |
| `utility_shortage.json` | Two separate water networks with priority consumers, tanks and an interruptible feed |
| `construction_site.json` | Delivery contract, protected scaffold and a staging blueprint with two connected scaffold bays |
| `waterfront.json` | Two piers, a vessel route around a dry island and a berth blocked by draining its water |
| `space_outpost.json` | An open-door mission room assembled from permitted HanX modules, a landing strip, supplied ships and a surface supply contract |

From the project root, use the Godot 4.7.1 console executable.

```powershell
godot_console --headless --path . --script res://tools/test_asset_expansion_golden.gd -- --test --packages
```

The test writes Studio sessions and the optional standalone outpost project under `output/verification/asset_expansion/P7/golden/`. To regenerate native 1480 × 900 screenshots separately, run the command with `--capture` in place of `--packages` and omit `--headless`. The preview fixtures in this directory use their own formats and test entry points.
