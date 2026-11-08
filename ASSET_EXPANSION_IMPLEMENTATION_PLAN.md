# IsoCity asset-informed implementation plan

Status: proposed implementation backlog. No feature in this document is marked implemented by this planning task.

Prepared against the local v0.8.0 source and asset audit on November 5, 2026. Runtime available locally: Godot 4.7.1. Re-read relevant source before implementing; method names below are verified at this checkpoint, while paths explicitly marked **new** are proposed.

## 1. Purpose and navigation

Implement the 60 recommendations from the asset-informed reassessment without losing the existing editor, nested interiors, economy, cooperative authoring, or playable exports. Keep the creative sandbox usable with every new simulation disabled. Deliver small complete features rather than registering controls for unfinished systems.

- [Evidence and product direction](#2-evidence-and-product-direction)
- [Repository map](#3-repository-map)
- [Cross-cutting engineering contracts](#4-cross-cutting-engineering-contracts)
- [Phased delivery](#5-phased-delivery)
- [Shared data contracts](#6-shared-data-contracts)
- [Existing feature improvements: I01–I20](#7-existing-feature-improvements)
- [New features: N01–N20](#8-new-features)
- [Interface improvements: U01–U20](#9-interface-improvements)
- [Code examples](#10-code-examples)
- [Verification and performance](#11-verification-and-performance)
- [Implementation-agent handoff](#12-implementation-agent-handoff)

IDs are stable. A release may implement tickets in dependency order rather than numeric order. Dependencies refer to IDs here, not the older completed 60-item tracker in `IMPLEMENTATION.md`.

## 2. Evidence and product direction

### 2.1 Asset baseline

The full audit is in `output/asset_reassessment/REASSESSMENT.md`; machine-readable details are in `asset_inventory.csv`, `assets.json`, `summary.json`, `source_files.csv`, and archive inventories in that directory. `output/` is ignored by Git. If handing this plan to a separate checkout, copy the audit artifacts explicitly or regenerate them; do not assume those files travel with a commit containing this plan.

| Evidence | Engineering implication |
|---|---|
| 6,233 catalog entries: 5,614 sprites and 619 models | Preserve IDs and existing mixed-world placement. Catalog count is not a unique-subject count. |
| 81 library source groups; 47,747 sprite-view records | Precompute family/search indexes. Do not scan every view on every UI refresh. |
| 25 village subjects → 450 entries; 25 water-tower subjects → 450 entries; 25 bonsai subjects → 250 entries | Build explicit family/appearance relationships; preserve all original variants. |
| Ten 36-item furnishing kits | These are delivered sprites, even though pack names say “3D pixel art.” Do not promise editable meshes. |
| HanX School 50, Shop 52, Construction 46, GasStation 31, Traffic 52, Park 67, City 37 | Start with visually consistent everyday neighborhoods and activities. |
| 114 SWAT models, including three skinned characters; no embedded animation clips in the catalog models | Rig detection is not animation availability. Static poses and K9 meshes need separate treatment. |
| Existing animated sprite families | Reuse action metadata; do not split every action into an independent citizen. |
| Power plants, batteries, pipelines, wells, towers, and transformer art | Utility mechanics have strong art support; connections, simulation, and overlays still need implementation. |
| Spaceships II thumbnails are uniform placeholders; original preview GIFs exist | First release should fix real discoverability failures before adding a space simulation. |
| Existing zoning catalog uses a small building list; four neighborhood themes | Expand existing content-driven systems before creating another generator. |
| HanX Shop building models have no business catalog defaults | A small explicit metadata change can make existing city-life systems more useful. |

Audit limits: catalog/file/metadata coverage was exhaustive within the inventoried project; visual review was representative across all source groups, not every frame or collision mesh. The audit did not certify every asset's collisions, usable approach, rig quality, redistribution status, or exported runtime behavior.

### 2.2 Product priorities

1. Make existing assets understandable and correctly integrated.
2. Make interiors and neighborhoods useful: schools, shops, garages, gardens, parks, and deliveries.
3. Add utilities and modular construction with clear connectivity tools.
4. Add optional specialized activities, boating, scenarios, and space content.

Preserve both the simple consumer shell and the precision workspace. Full metro simulation, broad tourism management, ecological simulation, and sewer hydraulics are not part of these 60 tickets. Do not quietly expand water supply into a physically accurate fluid solver or the space theme into a flight-combat game.

## 3. Repository map

All paths in this document are repository-relative unless explicitly absolute. Workspace at planning time: `F:\dev\IsoCity`.

| Area | Existing files and integration points |
|---|---|
| Main editor | `scripts/builder/studio.gd` extends `studio_base.gd`, which extends `interface.gd`; `scenes/builder.tscn`. Prefer small helper modules over growing the main script. |
| Commands and mutations | `studio.gd::_command`, `selection_items`, `changed`, `finish_edit`, `shared_authority`; `command_palette.gd`, `control_settings.gd`. |
| Simple UI | `consumer_shell.gd::matches`, `card_name`, `open_sheet`, `open_drawer`, `over_canvas`, `layout`; `consumer_theme.gd`. |
| Asset catalog | `scripts/catalog.gd::_load_registry`; merges `catalog_registry.json`, `imported_registry.json`, `supplemental_registry.json`, `swat_registry.json`. |
| Library | `asset_library.gd::_init`, `find`, `pack_name`, `icon`, `directional_icon`; model scene-directory discovery; `custom_assets.gd::register`. |
| Browsing | `asset_browser.gd`, `asset_search.gd`, `asset_card.gd`; hover/dialog animation previews already exist. |
| Asset generation | `tools/import_extra_assets.py`, `prepare_supplemental_assets.py`, `prepare_supplemental_characters.py`, `prepare_supplemental_models.py`, `integrate_supplemental_assets.py`, `prepare_swat_pack.py`. Avoid hand-editing generated files without updating their generator/overlay. |
| World rendering | `world_2d.gd::apply`, `world_3d.gd`, `asset_instance.gd`, `asset_behavior.gd`, `model_in_2d.gd`, `sprite_in_3d.gd`. |
| Geometry and placement | `grid_fit.gd`, `layout_alignment.gd`, `arrange_tools.gd`, `rotation.gd`, `orientation.gd`, `entrance_anchors.gd`, `piece_selection.gd`. |
| Documents and history | `document.gd::{valid,normalize,checkpoint,finish_checkpoint,record_completed_change}`, `document_delta.gd::{between,apply}`. |
| Nested rooms | `interior_tools.gd::{root_document,prepare,start,flush,leave}`, `floor_document.gd`, `floor_plan.gd`, `floor_entrances.gd`, `room_traversal.gd`, `interiors.gd`. |
| Save/recovery | `studio.gd::{session_data,write_project,load_project}`, `project_store.gd::write_json`, `project_repair.gd::{world,object}`, `json_recovery.gd`. |
| City simulation | `citizen_*`, `traffic_*`, `business_*`, `service_*`, `transit_*`, `zone_*`, `economy_*`, `scenario_*`. Existing convention: pure plan, runtime, editor tools. |
| Props and driving | `prop_plan.gd`, `prop_runtime.gd`, `prop_tools.gd`, `driving_plan.gd`, `driving_runtime.gd`, `driving_tools.gd`. |
| Terrain | `terrain_plan.gd`, `terrain_tools.gd`, `terrain_navigation.gd`, `terrain_traversal.gd`, `terrain_road_policy.gd`; 2D/3D presentation modules. |
| Planning and assemblies | `blueprint_plan.gd::{valid,construct,rectangles}`, `blueprint_tools.gd`, `studio.gd::{paste_objects,choose_assembly}`, `creation_share.gd`. |
| Co-op | `cooperative_tools.gd::{observe,authority}`, `cooperative_session.gd`, `cooperative_plan.gd::{allowed,touched,used_assets}`, `cooperative_merge.gd`, `cooperative_wire.gd`. |
| Playable export | `exporter.gd`, `play_scene.gd::{_ready,_process}`, `portable_export.gd::{collect_document,collect_asset,make_registry}`, `creation_share.gd`. |
| Regression | `tools/test_*.gd` SceneTree tests, `tools/verify_scenes.py`, feature-specific `verify_*_portable.py`. |

### 3.1 Existing invariants that are easy to miss

- Pixel and 3D are separate documents saved together, not two projections of the same city.
- Either document can contain sprites and models. Asset mode and document mode are different concepts.
- `FloorDocument` presents a selected floor but stores chronological history in a canonical owned-room document. Never invent independent per-floor undo stacks.
- `studio.changed()` invalidates simulations, flushes interiors, reconciles economy, updates dirty state, and observes co-op changes. Mutating a dictionary without that route bypasses important behavior.
- `selection_items()` filters editable selection; check its current implementation instead of directly iterating raw selection IDs.
- Runtime positions, service requests, passenger queues, and activity inventories are mostly transient today. Authored settings and economy accounting persist. Do not silently change this product contract.
- Generated content, future zoning candidates, unbuilt blueprints, and runtime-spawned assets need export dependencies even when not currently instantiated.
- Existing exports include objects hidden during editing. Preview visibility and export inclusion are different policies.
- `portable_export.gd::collect_asset` rejects assets whose metadata has `source_export_allowed=false`. Keep that behavior; do not bypass it to make a demo pass. Test prohibited-content errors and allowed-content exports separately.

## 4. Cross-cutting engineering contracts

### 4.1 Module boundaries

Use the existing `*_plan.gd` / `*_runtime.gd` / `*_tools.gd` pattern.

- Plan: validated, bounded input; pure calculations; no scene-tree mutation; deterministic output for equivalent normalized inputs.
- Runtime: owns actor nodes, clocks, reservations, and transient results; supports configure/reconcile, pause, reset, and shutdown.
- Tools: edits authored documents through existing history/economy/co-op paths; projects runtime diagnostics into UI.
- Presentation: 2D and 3D adapters consume the same semantic state. Avoid duplicating rules in separate visual managers.

Create shared helpers only when at least two concrete features need them. A modest activity reservation helper is justified; a generic visual scripting engine is not necessary for laundry or school attendance.

### 4.2 State ownership and serialization

| State | Owner | Persist? |
|---|---|---|
| Assets, family IDs, semantic tags, connector definitions | Catalog/metadata | Yes, versioned catalog data; not copied into every object. |
| Object overrides, schedules, routes, configured facilities | Authored document | Yes, history/recovery/export/co-op aware. |
| Reservations, queues, actor transforms, current interaction progress | Runtime manager | No by default; explicit future save-session work only. |
| Inventory or stock required by an economic challenge | Explicit account/progress schema | Yes only after transactional persistence is designed; never smuggle it into the temporary business inventory. |
| Favorite collections and most browser preferences | User preferences | Yes locally; must not dirty city content. |
| Project-specific allowed palette/theme | Workspace or authored project config, as explicitly chosen | Persist with the project; separate view filtering from gameplay restrictions. |
| Camera previews and generated thumbnails | Derived cache | Rebuildable; keyed by source hash + renderer/settings version. |

Stable references must contain document scope and object UID. A string like `chair_1` is not globally unique across worlds, building copies, and floors. Proposed scope: `{world, owner_uid, floor_uid}` with empty owner/floor for exterior. Future deeper nested buildings require an owner-path array; either support that or reject unsupported depth explicitly.

### 4.3 Validation and repair

For every new saved field:

1. Add optional-field validation to `Document.valid` and the relevant pure plan.
2. Preserve old documents when the field is absent. New simulations default off.
3. Validate types before casting. JSON round trips turn many integers into floats; accept finite integral numbers where appropriate, reject fractional counts, booleans, NaN, and infinity.
4. Bound string length, list size, numeric range, nesting, and reference counts.
5. Add repair in `project_repair.gd`; retain original invalid fragments in its report and disable only the damaged feature where possible.
6. Preserve unrelated extension fields; never replace a whole object with the defaults of one subsystem.
7. Validate references after the whole document is available. Do not reject a forward reference just because its target was parsed later.
8. Make migrations idempotent, with a clear version and a recovery copy before destructive interpretation changes.

Avoid broad format-version changes for optional additions. If a new version is necessary, update project load, repair, cooperative wire compatibility, sharing import, and portable source reopening together.

### 4.4 Transactions, money, and history

- Finish pending gestures before applying a panel command.
- Compute the intended changes first; return early on no-op. The base Document does not universally remove empty history entries.
- Record one checkpoint per user gesture or atomic construction transaction, not per frame or object.
- Apply changes through the current document adapter and call `studio.changed()`; account for rollback replacing dictionary references.
- Do not retain stale object dictionaries across economy reconciliation, Undo, floor switches, or co-op acceptance.
- Before bulk construction, quote the full intended transaction. If it cannot be paid, preserve all proposals and current funds. Do not partially delete proposals after rejecting a purchase.
- Reuse `economy_plan.gd::quote` and its purchased-content tracking. Do not charge once in UI and again in the authoritative host.
- Automatic starter interiors are currently complimentary; later edits and duplicated furnishings are charged. Preserve that distinction.
- Recurring simulation revenue is a separate transaction from construction pricing. Give each job completion a stable receipt ID and ensure replay cannot pay twice.

### 4.5 Determinism, clocks, and budgets

- Sort IDs before seeded choices or tie-breaking. Do not rely on dictionary order, wall-clock time, `randi()` globals, or display names for simulation identity.
- Existing citizen time is a useful source for daily schedules. New systems must not each advance their own incompatible “hour.” Adapt one explicit world clock; UI preview time jumps must not award skipped work.
- Use fixed simulation steps or bounded accumulated time. Define whether a long pause loses time or retains bounded debt; never process an unbounded backlog on resume.
- Existing interior visits suspend several exterior systems. N01/N07/N12 must deliberately define whether offscreen schedules advance; preserve pause behavior until that change is tested.
- Plan routes incrementally; cap expansions per tick and pending jobs. Cache by graph revision, traveler profile, scope, start, and destination—not just endpoints.
- Failures are states with reason codes and retry triggers. Rechecking an unreachable path every physics frame is not a recovery strategy.

### 4.6 Coordinates and geometry

This codebase has multiple coordinate conventions. Do not invent one universal `Vector2(position[0],position[1])` conversion.

- `traffic_plan.gd::metric/world` convert between saved positions and traffic/terrain ground space. In 2D, metric is `(x/16+y/8, y/8-x/16)`; in 3D it is `(x,z)`.
- `citizen_plan.gd::metric/world` use a different 2D navigation representation. Use the subsystem's adapter when exchanging routes.
- `floor_plan.gd` documents room grid coordinates for 2D links and metres for 3D links. Current maximum is eight floors, 32 links, 16 entrances; minimum floor gap is 2.4 metres.
- Sprite source views can change anchors and footprints. A rotation of artwork is not equivalent to rotating an actual mesh.
- Connector points are authored in asset-local coordinates, transformed through scale, world rotation, source view, and floor elevation. Reuse existing anchor helpers wherever their conventions match.
- Treat any broad-phase footprint intersection as a candidate, not proof of a blocked doorway. Preserve passages and low/overhead clearance.

### 4.7 Co-op and export are feature requirements

Co-op presently shares authoring, not a fully synchronized multiplayer life simulation. Do not imply shared player inventories or identical transient actors merely because document edits synchronize.

For new authored arrays, extend delta identities and co-op touched-area computation. Any new global settings need a host/participant policy. Host validates and charges accepted content exactly once. Rejected local proposals retain a useful explanation and cannot leave actors or reservations behind.

For runtime changes, integrate both Studio and `play_scene.gd`. For data-only dependencies, extend all relevant collectors: portable export, creation sharing, co-op required assets, and future-content generation. Dynamic catalog entries must be subsetted or explicitly copied into portable registries; having the editor's complete catalog available can conceal missing dependencies.

### 4.8 UI principles

- Extend the current six-activity dock and focused drawers. Do not add 20 permanent dock buttons.
- Keep basic actions in simple view; detailed graphs, profiling, and exact anchors belong in expandable controls/precision workspace.
- Register commands once and route both interfaces through them.
- Respect remapped controls, keyboard canvas operations, text scaling, high contrast, focus return, and the 960×640 minimum layout.
- Hide visual editing overlays in photo mode and route pointer events through existing overlay hit-testing. Opening a drawer must never paint underneath it.
- Display useful user reasons, not raw IDs, JSON keys, or exception stacks.

## 5. Phased delivery

All phases are part of the proposed scope. “Later” means scheduled after dependencies, not silently dropped. Use effort labels S/M/L/XL for relative scope; do not interpret them as calendar promises.

| Phase | Work | Exit condition |
|---|---|---|
| P0 — baseline and integration contracts | Capture existing save/export fixtures; catalog audit; shared identity and compatibility decisions | Known baseline, no game-content changes, first implementation slice selected. |
| P1 — reliable library | I01–I06; U01–U09, U16, U17; family/preview metadata | Browse accurate previews and names, inspect variants/animations, place assets with useful defaults. |
| P2 — useful places | I07, I13–I16, I20; U02/U10/U12–U15/U18; shared activity reservations | Build and explore furnished school/shop/garage rooms with valid interaction sites; history, budget, recovery, export pass. Full school schedules arrive in P3. |
| P3 — streets and work | I10–I12, I17; N01–N03, N07, N16; U19/U20 | Signals, fleet choices, rerouting, school/retail/delivery/vehicle-care loops work in a small city. |
| P4 — connected construction and utilities | I08/I09; N04/N05/N18; U11 | Author connected walls/pipes/paths; utility supply is deterministic and visible. |
| P5 — everyday activities | N06, N08–N13, N15, N17; I18 | Garden/cooking/laundry/fitness/arcade/camping/pet/cycling/village activities with tested cancellation and results. |
| P6 — specialized environments | N14/N19/N20; remaining rendering work I19 | Boating, emergency scenarios, and optional space theme with explicit capability limits. |
| P7 — release integration | Every ticket's remaining export, accessibility, co-op, performance, documentation evidence | 60/60 individually verified; no placeholders counted as completed features. |

I19 performance measurements start in P0/P1 and continue when scene composition changes. U19 diagnostics should ship with each system, not wait for P7. Shared foundations are extracted from the first complete use case, not implemented as a speculative framework months before a visible feature.

### 5.1 Recommended first three changesets

1. **Library thumbnail repair:** I05 only, real Spaceships II previews, deterministic fallback, regression image checks, no ID changes.
2. **Business defaults:** I01 for an explicit reviewed subset of HanX shops, preserving opt-outs and save/export compatibility. Do not simultaneously add school simulation.
3. **Family browser:** I02 with U03/U04/U06, family indexes and truthful animation badges; preserve exact underlying asset IDs and current favorites.

Use each completed slice to validate the plan's conventions before expanding scope. Do not amend the older tracker to claim these new 60 tickets were previously completed.

## 6. Shared data contracts

The following schemas are **proposed**, not already supported. Use explicit adapters and validation before saving them.

### 6.1 Catalog metadata overlay

Create `resources/catalog/asset_metadata.json` (**new**). Keep stable IDs as keys and generated import data intact. Load the overlay after native/supplemental/custom descriptors are registered; define custom-asset precedence explicitly.

```json
{
  "version": 1,
  "assets": {
    "3d:HanX_Shop/Shop_Cafe": {
      "family_id": "hanx/shop/cafe",
      "theme_ids": ["hanx_modern"],
      "tags": ["cafe", "food", "retail"],
      "aliases": ["coffee shop"],
      "content_kind": "object",
      "animation_status": "static_mesh",
      "task_ids": ["furnish_cafe"],
      "connector_set": ""
    }
  }
}
```

Capabilities must be computed from actual runtime/catalog eligibility plus per-instance overrides. A tag of “vehicle” must not automatically produce a “Drive” badge. New overlay files containing IDs must be dependency-scanned; strings not beginning `res://` are not handled by `collect_values` as resource paths.

For village/tower variants, store `family_id` + `palette_id` + `lighting_id`, with source view in its existing direction data. Do not embed the selected view into `family_id`. Derive a family manifest once during catalog preparation; require manually reviewed mappings for ambiguous source names.

### 6.2 Authored activities and facilities

Prefer a new optional `activity_sites` collection for multi-object facilities, with scalar per-object overrides only for independent devices. Proposed records:

```json
{
  "uid": "site_school_a",
  "kind": "school",
  "owner_uid": "building_a",
  "floor_uid": "ground",
  "enabled": true,
  "schedule": {"open_minute": 480, "close_minute": 900},
  "stations": [
    {"uid": "desk_station_a", "object_uid": "desk_a", "action": "study", "capacity": 1}
  ]
}
```

Store the world at collection ownership rather than repeating it inconsistently in every record. For exterior sites allow an empty owner/floor; for interior sites resolve the owner first. In the first version, limit a site to one building/floor or specify multi-floor scope formally—do not infer it from display names.

Proposed limits: 128 sites/world, 64 stations/site, 512 queued/active jobs/world, 128 diagnostic history entries. These are initial design bounds, not existing constants; tune against measured scenes and document any change.

Runtime job: `{uid, scope, actor_uid, site_uid, station_uid, phase, remaining, reservation_token, completion_id, reason_code}`. A job is never a Godot Node serialized inside city data. States: `queued → travelling → reserved → active → completed`; alternate terminal states `cancelled`, `failed`; `blocked` is retryable with a bounded retry policy.

### 6.3 Networks

New optional `utility_nodes` and `utility_edges` collections, using stable `uid`s, bounded references, and service kind `water` or `power`. Connect to actual placed endpoints; do not infer connectivity solely from overlapping bounding boxes.

```json
{
  "uid": "edge_power_01",
  "kind": "power",
  "from": {"object_uid": "generator_a", "socket": "output"},
  "to": {"object_uid": "shop_a", "socket": "input"},
  "capacity": 500,
  "enabled": true
}
```

Use integer simulation units initially. Declare units in UI: e.g. abstract power units and water units per tick. Component supply budgeting is acceptable for the first version only if the UI does not imply pressure, voltage drop, or physical fluid behavior. Edge capacities require a real bounded flow algorithm; do not advertise them while using an unlimited connected-component sum.

### 6.4 Collections needing special integration

For `activity_sites`, `utility_nodes`, `utility_edges`, future `construction_jobs`, and assembly blueprints: update `Document.valid`, repair, normalization where needed, `document_delta.gd` identity lists, co-op spatial protection/global authority, duplication UID remapping, dependency discovery, editor/export runtime setup, and save/load tests. Floor canonical metadata must not be inserted into child rooms in ways that violate `FloorPlan.FIELDS`.

## 7. Existing feature improvements

Each ticket below includes the intended implementation, edge cases, and completion evidence. Every ticket also inherits section 4 and the verification matrix in section 11.

### I01 — Complete functional defaults [M; P1]

**Files:** `resources/catalog/{businesses,citizen_roles,city_services,props,economy}.json`; relevant preparation scripts; `asset_behavior.gd`; existing business/citizen/service tests.

Create a reviewed mapping keyed by exact asset ID for the eight HanX shop buildings and selected school/garage/civic assets. Map supported shops to existing `cafe`, `shop`, or `service` kinds. Do not add `school` to `CitizenPlan.ROLES` before N01 introduces its schedule model. Add source-accurate approaches where absent; a visually recognizable building currently classified as decoration needs explicit behavior and entrance data too. Generated defaults should come from a repeatable overlay/compiler, not ad hoc filename inference at runtime.

**Edges:** explicit `business.kind=none` and `citizen_role=none` win; manual object overrides survive catalog changes; static display buildings may remain decorative; activating a new catalog default can change behavior of old cities. Record a catalog behavior revision and provide an opt-out/migration choice for material behavior changes, without blocking every ordinary edit.

**Done:** each mapped facility attracts the correct existing visit; disabled overrides remain disabled; JSON round trip, owned-room access, economy pricing, and permitted-content export pass. Assert unknown filenames never acquire behavior automatically.

### I02 — Strengthen asset-family handling [L; P1; foundation for U03/U04]

**Files:** `asset_library.gd`, `asset_search.gd`, `consumer_shell.gd::{matches,card_name}`, `asset_browser.gd`; new metadata overlay/compiler.

Build `family_id → member IDs` indexes once at library load. Represent palette/light quality as explicit dimensions and choose a deterministic default member. Preserve exact member IDs in saved objects, favorites, assemblies, and clipboard data. Existing hard-coded variant collapsing becomes a consumer of the index, with a safe legacy fallback while mappings are incomplete.

**Edges:** a family can lack one palette/view combination; importing new members must not change an existing object's appearance; favorites may include multiple members; distinct geometries must not be merged because names share prefixes; all-variants searches must remain possible.

**Done:** village/towers each show 25 designs when grouped, all 450 entries remain accessible, typed search can reveal individual variants, and reopening old saves preserves IDs/art. Index build and query costs are measured.

### I03 — Finish composite-image cleanup [L; P1]

**Files:** `tools/import_extra_assets.py`, source-specific manifests, `imported_registry.json`, `repair_assets.gd`, `grid_migration.gd` as applicable.

Review sampled atlas-like entries in MyArt, isometricvill, cars, flags, and ship groups. Add explicit crop rectangles, frame grouping, alpha treatment, source-view pairing, and ground-contact anchors. Assign `content_kind` values such as `object`, `atlas`, `reference`, `background`, `showcase`; browse object content by default, retaining deliberate scenery use elsewhere.

**Edges:** a combined image may be a legitimate assembled scene; transparent padding can carry tile phase; automatic connected-component splitting can separate one object's detached details; a spritesheet can encode animation rather than many objects. Do not delete old IDs or silently replace a placed atlas with one arbitrary crop.

**Done:** reviewed replacements have visual contact sheets, stable crops, proper anchors, and a migration/replacement map. Existing source art and legacy placements remain recoverable. Re-running preparation is idempotent.

### I04 — Improve imported names [M; P1; depends I02/I03]

**Files:** metadata overlay, `asset_search.gd`, `consumer_shell.gd::card_name`, `asset_card.gd`.

Add reviewed display names and aliases for opaque row/column or source-ID entries. Keep `source_name` and pack provenance visible in details. Names describe the actual object; identify compound scenery as such. Search aliases must not create duplicate asset results.

**Edges:** same human name in multiple packs; numeric names that are genuine identifiers; Unicode and apostrophes; localization-ready display text versus stable IDs. Never rename files or IDs solely to improve display text.

**Done:** a fixture set of ordinary queries retrieves the intended formerly opaque objects, exact source-name search still works, and grouping/favorites/saves are unchanged. Human review of names is required; an automatically generated label alone is not evidence of correctness.

### I05 — Repair and validate previews [S/M; P1; first slice]

**Files:** `tools/prepare_supplemental_models.py`, `tools/render_supplemental.gd`, `asset_library.gd::icon`, `import_thumbnail.gd`, model metadata.

Fix source preview lookup for low-detail models whose GIFs live beside the full-detail edition. Prefer rendering the active prepared model for faithful scale/material appearance; source GIFs are a fallback. Capture after the viewport is rendered, fit actual bounds, preserve alpha, and cache by source hash plus preview settings. Detect near-uniform thumbnails and route them to a visible missing-preview state.

**Edges:** tiny satellites versus wide ships; transparent or monochrome legitimate art; negative source bounds; camera inside geometry; first GIF frame is blank; absent source GIF; renderer unavailable; source changes invalidate cache; file writing failure keeps the old good preview.

**Done:** all 25 Spaceships II entries have meaningful recognizable thumbnails, reviewed beside source previews. Automated image checks flag the previous flat placeholders without rejecting legitimate simple tiles. Rebuilding does not modify model geometry or IDs.

### I06 — Standardize character action mapping [L; P1/P2]

**Files:** `prepare_supplemental_characters.py`, `scripts/character_animation.gd`, `iso_character.gd`, `sprite_view.gd`, `citizen_runtime.gd`, `player_3d.gd`, character registry metadata.

Define semantic actions (`idle`, `walk`, `run`, then supported task actions) and map each family to source clips, direction coverage, playback speed, loop mode, and compatible poses. Reuse current animation descriptors. Select clips by actual movement/task state, not asset filename. Keep standalone clips inspectable without populating the ordinary People browser with every action.

**Edges:** four/eight/many directional views; missing run uses validated walk fallback; missing sit must not play attack; frozen/static pose is not a loop; mixed sprite/model scale; 3D citizen appearance restrictions currently differ from 2D. SWAT rigged meshes need an explicit separate animation pipeline; do not label them animated.

**Done:** supported families animate in the correct directions without sliding when stopped; unsupported actions report/fall back honestly; exports include all referenced clips and views; resource caches are released on reset.

### I07 — Expand interaction anchors [L; P2; supports N01/N08–N11]

**Files:** `props.json`, `prop_plan.gd::source/anchor`, `prop_tools.gd`, `prop_runtime.gd`, `entrance_anchors.gd`, source-specific authoring tools.

Author approach, contact, exit, and facing for appropriate seats and equipment. Separate operator and customer positions where needed. Keep anchors tied to the relevant sprite view or actual mesh transform. Reuse the existing protection and custom-override UI; validate approaches with the same clearance used by runtime traversal.

**Edges:** object moves or rotates while occupied; scaled/tilted assets; blocked stand-up position; two users on one chair; floor removed; device is hidden or deleted; unsupported pose; sprite action view differs from idle footprint.

**Done:** representative classroom, gym, office, kitchen, and station objects have usable approach/exit cycles in both document modes and mixed asset combinations. Cancellation releases reservations, restores motion/collision, and never strands the player.

### I08 — Add modular connection snapping [XL; P4; supports N04/N05/N18]

**Files:** `arrange_tools.gd`, `grid_fit.gd`, `studio.gd::placement/paint`, `editor_feedback.gd`, new `connector_plan.gd`, `connector_tools.gd`, connector metadata.

Define connector type, local position, outward normal, up direction, size/profile, and allowed mates. Build a spatial index of candidate endpoints; select a compatible target within a screen-space tolerance, then solve transform alignment. Preview source and target sockets before commit. Store semantic connections separately from visual proximity when they drive utilities.

**Edges:** rotated/scaled source and target; negative/mirrored transform policy; incompatible diameters; occupied sockets; same-object connection; overlap allowed by geometry but blocked endpoint; equidistant candidates need stable tie-breaks; protected target; source view changes invalidate a 2D socket mapping.

**Done:** Gloria Station walls, SWAT training walls, scaffolds/fences, and selected pipes mate without gaps and retain undo/duplication/save behavior. Changing source scale cannot silently stretch the target or auto-connect incompatible services. See the tested 3D transform example; 2D requires its own adapter.

### I09 — Automatically connect terrain families [L; P4]

**Files:** `ground_brush.gd`, `terrain_tools.gd`, `terrain_tiles_2d.gd`, `terrain_presentation_2d.gd`, `tile_patterns.gd`, new authored terrain-family tables.

Map connection masks to specific shoreline, path, corner, cliff, and transition pieces. Derive topology from neighboring terrain/path cells, update only affected neighbors, and preserve original source-cell padding. Start with one complete family before mixing Rodwan, HanX, and other grid sizes.

**Edges:** missing mask variant; diagonals and inner corners; water at different levels; cliff height changes; manual overrides; protected neighbors; no complete 3D geometry equivalent for a sprite family; flood-fill caps; rotated ground conventions.

**Done:** closed pond, island, concave shoreline, path T/cross junctions, and cliff loop have visually correct edges. One stroke remains one undo step; repainting does not stack surfaces; unsupported transitions are explicitly marked rather than guessed.

### I10 — Make signs and lights functional [L; P3]

**Files:** `traffic_plan.gd`, `traffic_junctions.gd`, `traffic_runtime.gd`, `transit_runtime.gd`, `service_runtime.gd`, `traffic_tools.gd`; new traffic-control profiles.

Bind a sign/signal object to a road approach or intersection UID/cell and facing. Add one-way/stop/yield rules and phase-driven lights. Extend shared junction coordination so buses, service vehicles, ordinary traffic, and pedestrian phases respect one source of truth. Keep signal phase transient and authored timings persistent.

**Edges:** contradictory signs; lights deleted mid-phase; no road near sign; visual heading differs from road approach; crossing pedestrian already in junction; starvation; deadlock; all-red safety clearance; round-trip of bound road after edits.

**Done:** a four-way fixture demonstrates mutually exclusive conflicting movements, pedestrians clear before release, and every vehicle subsystem follows the same control. Existing unconfigured roads keep their current all-way-stop behavior.

### I11 — Expand simulated fleets [L; P3; depends I06 where actors need clips]

**Files:** `traffic_runtime.gd::spawn/pose`, `city_services.json`, `transit.json`, `driving.json`, `traffic_tools.gd`, export asset collectors.

Introduce explicit eligible fleet profiles: asset ID, probability, length/width, speed envelope, turning clearance, heading convention, and service eligibility. Replace fixed sedan/bus choices only after sizing logic uses the profile. Choose deterministically from valid installed entries; do not select every `vehicle=true` object.

**Edges:** sprite view/yaw mismatch; an oversized truck cannot use a narrow turn/bay; missing chosen asset; zero weights; different available assets among peers; vehicle changes while in transit; road-vehicle rules must exclude boats, aircraft, and static display gear.

**Done:** at least two compatible fleet styles run through intersections/parking without overlapping because of fixed sedan dimensions. Unspawned selected fleet members are included in portable dependencies; no chosen fleet causes a prohibited source-export bypass.

### I12 — Automatically reroute after edits [XL; P3]

**Files:** `traffic_runtime.gd::configure`, `traffic_plan.gd`, `traffic_junctions.gd`, `transit_plan.gd`, `transit_runtime.gd`, `service_dispatch.gd`, `service_runtime.gd`.

Increment a route graph revision only when relevant connectivity/clearance changes. Preserve a vehicle's actual position and valid current segment; enqueue replanning from a safe reachable anchor. Release obsolete junction/bay claims, preserve passengers/job identity, and accept results only if their graph revision and actor request still match. Ordinary traffic may choose another destination; transit/service jobs retain their intended stop/target unless the user changes it.

**Edges:** deleted current road under the vehicle; removed destination; disconnected graph; route changes again while planning; road reopened by Undo; slope/flood invalidation; altered parked bay; cycle of retries; hidden world; no safe anchor. Never teleport across a gap as a successful reroute.

**Done:** alternate-road fixture recovers without restart; disconnected fixture stops safely with a useful reason; unrelated edits preserve journeys; repeated edits do not leak claims or respawn all vehicles. The bounded BFS example is a reference for scheduling, not a replacement for lane/clearance planning.

### I13 — Building-specific starter interiors [L; P2]

**Files:** `templates.gd`, `interiors.gd`, `interior_tools.gd::prepare`, `floor_plan.gd`, `document.gd::complimentary_room`, new `resources/catalog/interior_kits.json`.

Map reviewed building families to room kits with functional zones, exit clearance, and explicit content dependencies. Instantiate once on first interior creation. Use existing owned-room persistence and floor history. Existing customized rooms are never regenerated because a catalog mapping changed.

**Edges:** missing furniture pack; building scaled externally; small shell; already-owned floors; user chooses an empty room; starter furniture budget versus later replacements; mixed native/mixed-mode assets; source-export restrictions; each duplicate requires new object/link IDs.

**Done:** school, café/shop, garage, and station starter rooms are navigable and independently editable. Save from inside, visit after reload, duplicate/delete/undo owner, and permitted-content portable export retain furnishings and exits.

### I14 — Residents use furnished interiors [XL; P2/P3; depends I07/I13]

**Files:** `citizen_plan.gd`, `citizen_runtime.gd`, `business_visits.gd`, `business_runtime.gd`, `interiors.gd`, `room_traversal.gd`; new scoped activity scheduler.

Represent transitions as an itinerary across exterior entrance, floor link, station approach, service, and exit. Keep actor/job identity stable while switching rendering contexts. Offscreen rooms need a lightweight logical occupancy representation; do not instantiate all owned rooms simultaneously. Reuse queues and reservations instead of making every NPC walk to the same seat.

**Edges:** building/room/floor removed while occupied; player enters a room already logically occupied; elevator capacity; current exterior suspension behavior; unreachable return path; building copied; shared floor history undone; rendering context differs from simulation scope.

**Done:** two residents enter a shop/classroom, occupy distinct stations, complete an activity, and leave; player visits mid-activity without duplicate actors or lost jobs. Document content remains unchanged by ordinary transient actor motion.

### I15 — Expand zoning candidates [M/L; P2; depends I01/I02]

**Files:** `zoning.json`, `zone_plan.gd`, `zone_runtime.gd`, `zone_tools.gd`, `terrain_site.gd`, `economy_plan.gd`, export collectors.

Define candidate families by zone, theme, footprint limits, entrance suitability, density, and price. Filter eligibility before seeded weighted choice; choose a concrete appearance member after the family. Prevent a family with 18 palette variants receiving 18 times another building's probability.

**Edges:** no eligible candidate; insufficient budget at completion; footprint blocked by moving actors; terrain grade; construction plan survives catalog updates; manual asset replacement; completed building removed while lot remains; protected layers.

**Done:** several distinct buildings grow in valid lots, theme constraints hold, all invalid lots show specific reasons, deterministic seeds are stable for a fixed catalog revision, and future chosen assets are packaged.

### I16 — Expand neighborhood themes [M/L; P2; depends I02/I15]

**Files:** `neighborhoods.json`, `neighborhood_plan.gd`, `neighborhood_tools.gd`, `tools/test_neighborhood_foundation.gd`, `tools/test_neighborhood_plan.gd`, and related neighborhood workflow/export tests.

Create curated palettes for HanX modern, Korean street, village, industrial, and historical settings. Each palette specifies available building families, compatible ground/roads, parks, and prop density. Add preview of the full generated proposal and keep generation deterministic. Reuse existing planning/commit flow rather than directly spawning random nodes.

**Edges:** incomplete Korean free pack; mixed architectural scales; historical sprites may be flat in 3D; absent assets; smaller terrain bounds; choosing no buildings; repeated seed with different catalog revision.

**Done:** each shipped theme has a reviewed starter fixture, traversable entrances, compatible assets, stable generation, cost quote, undo, and portable source reopening. Explicitly report limited theme variety rather than filling gaps with unrelated styles.

### I17 — Improve construction-stage scenery [M/L; P3]

**Files:** `zone_visual_2d.gd`, `zone_runtime.gd`, `zone_plan.gd`, `asset_instance.gd`, construction-stage metadata.

Attach temporary stage dressing from HanX Construction: foundations/rebar → frame/scaffolding → finishing materials. Treat it as runtime presentation of a lot, not separately purchased permanent objects unless the user explicitly converts it. Align scale to lot bounds and avoid covering access routes.

**Edges:** large/small lots; paused progress; preview versus authored stage; material piles colliding with pedestrians; scene reload mid-stage; repeated redraw creating duplicates; unavailable source pack; two lots share a boundary.

**Done:** each construction phase is visibly distinct, does not inflate budget or saved-object counts, and disappears exactly once on completion/cancellation. Package all future stage assets, not only the currently visible phase.

### I18 — Place-specific ambience [M; P5]

**Files:** `ambience.json`, `ambience_context.gd`, `ambience_plan.gd`, `ambience_runtime.gd`, `ambience_bank.gd`, `ambience_tools.gd`, `tools/build_ambience_audio.py`.

Add original/licensed sound sources for school, arcade, workshop, market, and harbor categories. Select loops/events from activity state and scope, not merely the presence of decorative art. Reuse distance, volume, mute, visibility, room context, and saved object overrides. Budget simultaneous voices.

**Edges:** many colocated devices; crossfade on entering floors; audio disabled; missing/unsupported stream; activity cancelled mid-sound; pause; conflicting object overrides; no source audio actually supplied for a proposed category.

**Done:** audio evidence includes actual playable clips and audible runtime review, with no doubling/leak after repeated room visits. Existing mute/remapped shortcuts and portable audio dependencies continue to work.

### I19 — Asset-aware rendering budgets [L/XL; start P0, finish P6]

**Files:** `model_in_2d.gd`, `world_3d.gd`, `asset_instance.gd`, model metadata, `asset_library.gd` preview cache; new profiler/report helper.

Measure geometry, material count, texture residency, model-in-2D render targets, and thumbnail cache usage. Choose supplied low-detail editions by explicit metadata, preserve high-detail sources, and apply visibility/distance policies to presentation only. Use bounded caches keyed by asset/view/appearance with invalidation. Investigate instancing only for genuinely shared static geometry/materials.

**Edges:** per-instance painted materials break batching; animation and interaction need live objects; culling removes collision accidentally; photo mode requires higher detail; sprites viewed at orbit angles; transparent objects; memory costs exceed triangle costs.

**Done:** before/after benchmarks on fixed scenes show improvement without visible popping beyond documented thresholds or gameplay changes. Do not claim a percentage improvement without captures/measurements. UI cost estimates label their uncertainty.

### I20 — Blueprint functional assemblies [XL; P2/P4; depends I08/I13 where needed]

**Files:** `blueprint_plan.gd`, `blueprint_tools.gd`, `blueprint_visual.gd`, assembly methods in `studio.gd`, economy, duplication and dependency collectors.

Add a versioned assembly proposal containing objects, owned interiors, roads, connection references, and activity-site definitions. Generate a complete remapping for every copied UID before resolving links. Validate location, access, protection, asset availability, and complete cost against a candidate document, then commit atomically.

**Edges:** internal references versus external city references; missing packs; outside utility connection unresolved; insufficient funds; invalid one component; nested floor limits; collaboration conflict after preview; manually edited proposal; no-op repeated commit.

**Done:** furnished shop/school-wing/service-compound fixture previews accurately, commits once, charges once, undoes completely, and preserves all links after save/export. Failed commit leaves proposals and city unchanged.

## 8. New features

These are new gameplay loops; generic existing appliance timers, visitor routines, or decorative assets are not sufficient completion evidence. Each loop should ship first as one coherent example with reusable foundations, then cover its declared asset set.

### N01 — School life [XL; P3; depends I07/I13/I14]

**Build:** new `school_plan/runtime/tools.gd`, `schools.json`; adapt citizen schedules and transit boarding, using the existing school building, desks, classroom, playground, and school bus assets.

Model enrollment/capacity, arrival window, classes, breaks, departure, and optional bus-stop assignment. Desks are reservable stations; school-bus trips use the shared road/junction and passenger machinery. Start with day schedules; do not invent family relationships or grade progression as prerequisites.

**Edges:** more pupils than desks; late buses; holidays/closed school; classroom removed; blocked school crossing; player enters during class; no child character family available—use an explicitly selected suitable placeholder without claiming age-specific art.

**Accept:** a small school day visibly changes occupancy and destinations, preserves transport/seat capacity, and ends without stranded reservations. Saving settings and loading restarts transient sessions predictably. A time jump does not falsely award full attendance.

### N02 — Fuel, charging, and vehicle care [L/XL; P3; depends I07/I11]

**Build:** new `vehicle_service_plan/runtime/tools.gd`; HanX pump/charger/car-wash/garage profiles; integrate `driving_runtime.gd` and delivery actors.

Add optional fuel/charge and condition only to opted-in vehicles. Service bays define compatible vehicle class, approach, queue, duration, price, and result. Fuel/charge quantities are bounded and separate from generic business-item inventory. Preserve creative driving defaults when disabled.

**Edges:** vehicle entered/exited mid-service; car wash has no supplied animation; occupied bay removed; long vehicle cannot fit; charge/fuel mismatch; insufficient funds; cancelled task must not double-charge; visiting an interior suspends the session.

**Accept:** drive to a valid bay, queue, service, pay once, and leave; incompatible vehicles receive a reason. Demonstrate fuel, EV charge, and one wash/repair action rather than merely changing a progress label.

### N03 — Local delivery jobs [L; P3; depends I11/I12 and shared jobs]

**Build:** new `delivery_plan/runtime/tools.gd`, reviewed vehicle/loading-site profiles; reuse service travel and traffic gates.

Represent contracts with pickup/drop-off scopes, item type/quantity, vehicle capacity, reward, deadline policy, and idempotent receipt. Visually move crates or a cargo indicator during loading/unloading. Implement player-driven delivery first or autonomous first, explicitly; completing both is the final ticket scope if both controls are exposed.

**Edges:** destination deleted, shop closes, cargo partially loaded, vehicle switched, graph invalidated, load saved/reopened, duplicate completion event, co-op authoring versus unsynchronized transient jobs.

**Accept:** a parcel travels between two actual sites, capacity is enforced, reward cannot be repeated, cancellation restores/settles stock under a stated policy, and export includes vehicles/items required by future jobs.

### N04 — Water supply [XL; P4; depends I08/U11]

**Build:** new `utility_plan/runtime/tools.gd` shared with N05; `water_profiles.json`; explicit node/edge authoring and overlays.

Start with source production, connected tower storage, and prioritized demand in integer units. Towers have per-family capacity defaults, not capacity multiplied by palette count. Define wells/pumps only when their art/metadata supports the role. Disconnected consumers get no supply. Add edge throughput only when implemented by a bounded flow solver; otherwise omit the field/UI.

**Edges:** loops, isolated towers, multiple sources, empty/full storage, water and power edges crossing, removed source, deterministic shortage distribution, negative quantities, flooded access, unloaded interior consumers, stored water versus daily supply units.

**Accept:** balance equations hold: opening stock + production = delivered + closing stock + explicitly modeled loss/spill. No creation of water through cycles. A visible outage and recovery occur by disconnecting/reconnecting a pipe. Sewage/pressure simulation is outside this ticket.

### N05 — Electricity supply [XL; P4; shares N04 graph]

**Build:** power profiles for supplied plants, batteries, generators, solar/wind art, substations, and consumers. Reuse shared graph storage, diagnostics, and authoring, not water-specific naming.

Define production, demand priorities, storage input/output limits, and optional weather/day influences. A plant model becomes functional through an explicit profile; nearby decorative pipes do not transfer electricity. Device effects should start with lamps, appliances, chargers, and businesses opting into service requirements.

**Edges:** simultaneous charge/discharge creating energy, zero-capacity batteries, changing time/weather, user switches off a consumer, source asset unavailable, cross-floor demand, co-op edits to a shared network, serialization of authored versus transient energy.

**Accept:** conservation tests, deterministic brownouts, visible consumer response, and recovery after a connection edit. The first model uses abstract units; real voltage/frequency/grid engineering is not claimed.

### N06 — Community gardening [L; P5; depends I07/N04 optional]

**Build:** new `garden_plan/runtime/tools.gd`, crop definitions, garden beds and greenhouse sites; use supplied tools/plants/soil/compost.

Plant → water → grow → harvest with explicit durations/yield, a limited inventory, and suitable interactions. Water utility linkage is optional; manual watering works without N04 enabled. Define seed and harvest costs/rewards only through shared receipts. Source art lacks every growth state; create reviewed states or use clearly labeled discrete indicators.

**Edges:** season changes, dry bed, player leaves, bed moved/deleted, pause/time jump, overflow yield, overlapping beds, intentional decorative plants, crop removed by Undo.

**Accept:** a full grow/harvest cycle changes actual state and produces a bounded result, with no reward from cancelled/incomplete crops. Decorative plant placement alone never starts unwanted farming.

### N07 — Market days [L; P3/P5; depends I01/I14/N03 optional]

**Build:** new market schedule/site profiles using HanX stalls and supermarket goods; extend existing business/runtime with event/site adapters.

Configure event windows, vendor stations, visitor capacity, queue locations, finite or creative stock, and cleanup. Replenishment can be abstract initially, then delivery-driven when N03 is enabled. Use event-owned temporary presentation without purchasing the same permanent stall every day.

**Edges:** closing while service is active, crowded exits, rain policy, repeated day wrap, stock exhausted, event disabled, temporary stall collides with permanent content, multiple markets overlap.

**Accept:** opening spawns/activates the configured market, shoppers use stations, stock/revenue follow the selected policy, and closing cleans up safely without deleting authored assets.

### N08 — Cooking workflows [L; P5; depends I07/shared jobs]

**Build:** recipe definitions and cooking-site adapter using kitchen cookware, appliances, café counters, and food art.

Reserve stations for preparation, cooking, and serving; check ingredients before starting; define when ingredients are consumed and refunds are possible. Reuse appliance visuals where valid but track a multi-step recipe, not just a renamed timer. Author recipe outputs with actual usable result IDs.

**Edges:** missing ingredient/utensil, power outage if opted in, dish abandoned between steps, stove deleted, two cooks compete, recipe changed mid-job, animation unavailable.

**Accept:** one complete recipe consumes the correct inputs, requires its stages, produces one result, and can be served through an existing business. Every cancellation point has a tested inventory policy.

### N09 — Laundry services [L; P5; depends shared jobs/N03 optional]

**Build:** laundry order/site adapter using washer/dryer/folding assets, baskets, detergent, and counter profiles.

Orders progress through receive → wash → dry → fold → return. Machines have capacities and reservations. Use stable order/item identity across stages; choose a deliberate policy for unattended machines continuing when the player walks away. Integrate utility requirements only when enabled.

**Edges:** batch too large, machine removed or switched off, capacity changes, order cancelled after washing, wrong customer receives output, duplicated machine clone, session reset during work.

**Accept:** queued orders use machines fairly, cannot occupy two machines with one reservation, and produce one completion receipt. Existing simple appliance interactions remain available for non-facility objects.

### N10 — Fitness and sports sessions [L/XL; P5; depends I06/I07]

**Build:** activity profiles for selected gym stations and one simple court activity; schedule/booking UI through shared sites.

Start with exercise-bike/treadmill/rowing interactions that have credible contact positions, then one ball/court activity with actual scoring or a defined goal. Distinguish an animated activity from a character standing next to equipment while a timer runs. Use supplied sports items as equipment, with new motion where needed.

**Edges:** insufficient participants, unavailable animation, ball out of bounds, equipment height/scale, spectator obstruction, pause/interior switch, user interrupts, station removed.

**Accept:** at least one station workout and one court activity have visible behavior, bounded session state, cancellation, and reusable task profiles. Do not imply support for every sport represented by a decorative item.

### N11 — Playable arcade games [L; P5; depends I07]

**Build:** arcade session controller plus small original minigame scenes; connect to the 20 existing cabinet profiles.

Replace generic timed completion only when a cabinet has a configured actual minigame. Share a few game types across suitable cabinet families (e.g. racer, rhythm, simple action) rather than promising 20 unique games. Use a focused overlay or screen surface, score submission, cancel/exit, and input isolation.

**Edges:** controls remapped, cabinet deleted mid-game, second player/visitor requests occupied cabinet, losing application focus, Escape conflicts, photo mode, save/reload during session, leaderboard size bounds.

**Accept:** at least two distinct playable game types respond to user input, score reproducibly under test inputs, and return control/camera correctly. Existing cabinets without a game keep an honest timed or decorative interaction label.

### N12 — Camping visits [L; P5; depends I07/I14/shared schedules]

**Build:** campsite site/profile with tent/shelter, sleeping capacity, picnic/campfire stations, check-in/out schedule, and park routing.

Reserve sites and assign guests; provide a full arrival → camp activity → rest → departure sequence. Begin with daytime/overnight scheduling, not survival needs. Campfires use existing switch/effect support where appropriate; add safe visual/audio extinguish behavior on end/reset.

**Edges:** campsite flooded, weather changes, no exit path, overbooking, player sleeps across time transition, fire left on, multiple rooms/worlds with same site UID, unavailable suitable sleeping pose.

**Accept:** two sites can host independent visits with visible occupation, correct capacity, and complete cleanup. Overnight time skipping must follow a declared global-clock policy and cannot duplicate other job rewards.

### N13 — Pet companionship [L; P5; depends I06/shared routing]

**Build:** pet ownership/follow adapter, explicit supported cat/dog animation profiles, interactions using park dog equipment and home resting spots.

Follow, stay, approach, rest, and return commands; bounded catch-up behavior and obstacle navigation. Assign a stable owner/pet relationship within a session or explicitly saved ownership config. Do not treat the `CATS ISOMETRIC ASSET PACK` label as proof of cat characters: the audited entries there are terrain blocks; use actual Pixel Isometric pet sprites.

**Edges:** owner enters vehicle/building/elevator; owner disappears; pet becomes stuck; leash/follow distance; no matching animation; deep water; switching between sprite/model worlds; co-op user identity.

**Accept:** a supported pet follows a route, waits, rests, and returns without teleporting through walls or blocking exits. Recovery behavior is visible and bounded; no claim of animated K9 support from static SWAT meshes.

### N14 — Boating and harbors [XL; P6; depends I08/shared routing]

**Build:** new water-route planner, vessel profiles, dock sockets, boarding/exit checks, and boat runtime. Use suitable supplied boat/ship artwork rather than assuming every ship image is a controllable vehicle.

Construct navigable regions from water level and vessel clearance; docks provide safe land/water transfer. Start with one controllable boat and one scheduled route. Preserve world camera/movement conventions and generate wakes only as presentation.

**Edges:** insufficient depth, disconnected water, changing water level, bridge clearance, occupied dock, shore moved during travel, no safe disembark point, static source background baked into sprite, large ship footprint, sprite limited facing coverage.

**Accept:** board, travel around obstacles, dock, and disembark safely; route deletion/flood edits fail predictably; all active claims clear on reset. Terrain water paint alone is not enough to pass this feature.

### N15 — Cycling and scooters [L/XL; P5; depends I11/I12]

**Build:** riding profiles for HanX Bicycle/Scooter and compatible rendered two-wheelers; route-mode access, racks, mounting/dismounting.

Reuse suitable portions of driving input and collision with distinct width, speed, acceleration, and allowed path classes. Define rider visibility/pose for static vehicle meshes. Treat cycle-lane art as an explicit tagged route connection, not automatic permission to drive anywhere painted similarly.

**Edges:** narrow gaps, stairs/curbs, head-on cycles, pedestrian crossings, bike rack removed, rider frame incompatibility, vehicle left indoors, transition to normal walking.

**Accept:** a route to a rack works in both worlds using declared supported assets; player/NPC respects path access and returns to walking at a clear location. Unsupported rider poses are documented and resolved before claiming full visual completion.

### N16 — Construction contracts [XL; P3/P4; depends I11/I12/shared jobs; I08 for connected modules]

**Build:** contract definitions, construction site manager, loading/material stations, vehicle eligibility, and objective adapter to existing scenarios.

First contract: deliver materials → install barriers/site equipment → complete a defined build step. Add machine tasks only with actual controllable parts or deliberately bounded whole-machine motion. Keep contract state separate from ordinary zoning stage dressing (I17).

**Edges:** removed site, construction inside protected area, wrong material, partially delivered loads, demolition/refund exploits, duplicate job receipts, unsafe spawn, static excavator arm without a rig, interrupted blueprint commit.

**Accept:** a contract requires real deliveries and placement/tasks, gives a single reward, survives configured persistence policy, and can fail/cancel without corrupting budget or city content. Decorative machinery passing a timer is insufficient.

### N17 — Village production chains [L/XL; P5; depends N03/N06/N08 where enabled]

**Build:** production recipes and facilities for reviewed village families: farm, granary, mill, bakery, smith, and market.

Use finite recipes and inventories with transfer jobs. Represent base building family once regardless of palette count. Schedule production in bounded ticks; cap stock and backlog; let creative mode bypass economy while maintaining understandable activity.

**Edges:** circular recipes, missing upstream goods, full output storage, same building appears in several roles, recipe changed mid-cycle, seasonal crop supply, demolition of stock owner, duplicate transfers.

**Accept:** a small grain→flour→bread chain conserves inputs, stalls meaningfully on missing supply, resumes after delivery, and sells once. Blacksmith production may start with abstract reviewed inputs; do not imply mining gameplay exists.

### N18 — Modular building authoring [XL; P4; depends I08/I13/I20]

**Build:** `modular_building_plan/tools.gd` and kit definitions for existing wall/door/window/floor pieces; room outline tool; opening placement; floor integration.

Start with one complete supported kit. Convert a drawn orthogonal room boundary to valid modules; resolve corners and door gaps; preview collision/access; commit as an editable assembly with owned structure metadata. Preserve manually placed modules and allow detaching from procedural control.

**Edges:** unsupported diagonal/curved boundary, wall length not divisible by module width, openings overlap corners, upper-floor gap, floor cutouts, mesh ceiling obstruction, sprite cannot show reverse face, replacing kit with incompatible dimensions, connection references on duplication.

**Accept:** users create a traversable room with a real doorway/window, resize it without silently deleting edits, connect a second room/floor, and export collision-correct geometry. Whole-building meshes are not magically decomposed into modular parts.

### N19 — Emergency-training scenarios [L/XL; P6; depends I07/I11/I12 and scenario extensions]

**Build:** scenario definitions for dispatch, establish perimeter, locate/assist an NPC, and return; integrate service requests, barriers, stations, and goal validation.

Use existing Fire Station PSX, medical/service, construction, and SWAT assets. Author conditions and objectives as bounded data, not arbitrary executable scripts loaded from shared files. Training is a virtual game activity; no real-world tactical simulation is needed to satisfy this ticket.

**Edges:** goals reference deleted objects, scene lacks required assets, response path blocked, static posed characters, repeated reward, challenge restarted mid-dispatch, user edits world to invalidate completed goals.

**Accept:** at least two different scenarios have observable actions, success/failure criteria, restart/stop behavior, and dynamic goal revalidation. Rigged SWAT motion is only enabled when an actual compatible animation solution is integrated.

### N20 — Optional space-outpost expansion [XL; P6; depends I05/I08/N18/shared jobs]

**Build:** curated space theme, outpost template, landing/docking profiles, supply-arrival jobs, and optional orbital visual layer for satellites.

Combine compatible Gloria Station/Exo-Lunar sprites with declared spaceship/satellite models. Separate scenery satellites from interactive docking vehicles. Start with scripted arrival/departure and exploration; retain future free-flight as a separately scoped extension rather than building a new physics game.

**Edges:** wildly different source sizes, no ship collision, no interior art for a hull, source lighting mismatch, multiple ships reserve one dock, interrupted arrival, missing model previews, performance in mixed 2D view, export restrictions on other included packs.

**Accept:** a small outpost supports safe exploration and a visible supply ship arrival/dock/unload/depart cycle, with resource cleanup and permitted-content portable export. It remains optional and does not change ordinary city controls.

## 9. Interface improvements

These tickets reuse existing asset preview, accessible focus, remapped controls, favorites, and basic/advanced workspace features. Avoid reimplementing them under new names.

### U01 — Theme-first browsing [M; P1; I02]

**Files:** `consumer_shell.gd`, `asset_browser.gd`, theme metadata.

Add visual theme collections above pack-level filtering: HanX modern, Pixel City, Village, Industrial, Space, Historical. Themes are many-to-many tags; pack filters remain available. A tile can belong to several themes without becoming duplicate entries. Keep an unrestricted Everything view.

**Edges/acceptance:** cross-style search exposes why an item appears; unknown/custom imports get a useful unclassified state; theme changes do not alter placed objects. Keyboard users can choose themes and return to the canvas; narrow screens wrap/scroll without hiding Clear filters.

### U02 — Task-based furnishing collections [M; P2; I13]

**Files:** consumer drawer, new task-collection definitions, `asset_library.gd` indexes.

Present “Furnish a classroom,” “Open a café,” “Build a campsite,” and “Set up a garage” as collections of complementary assets with optional essential/extra groupings. Collections browse assets; applying a complete interior is a distinct previewed action under U13.

**Edges/acceptance:** missing packs do not leave a task empty without explanation; an exterior asset is not silently placed inside; one task can span styles but defaults to compatible sets. Selecting an item preserves task context and existing single/repeat placement behavior.

### U03 — Separate designs from variants [M; P1; I02]

Display base-family count and member count separately. A collapsed card shows a real representative and a “Variants” action. Search and favorites reveal concrete selected members when relevant. Preserve current chosen palette across compatible family switches only when that exact combination exists.

**Edges/acceptance:** family size one needs no redundant expander; a favorite variant is not hidden by a different representative; filters producing only one member show it correctly; counts update after import. Village/tower design counts match the reviewed manifest.

### U04 — Independent appearance selectors [M/L; P1; I02]

**Files:** `asset_browser.gd`, `appearance_tools.gd`, source-view/rotation controls, family metadata.

Expose palette, baked lighting, source angle, and animation action as separate choices with a small live preview. Changing appearance member on an existing object is an explicit replace operation preserving compatible transforms and checking geometry/paint compatibility; do not overwrite the asset ID from a mere hover.

**Edges/acceptance:** invalid combinations disabled with reason; source angle versus world yaw labeled distinctly; custom paint cannot silently disappear on incompatible replacement; current selection in a mixed set shows Mixed. Cancel leaves scene and history unchanged.

### U05 — Capability badges [M; P1/P2; I01]

Compute badges from verified profiles: Enter, Drive, Use, Citizens, Business, Services. On library cards these describe default potential; on selected objects they reflect overrides and current availability. Distinguish “Supported” from “Ready now” where access/routes are required.

**Edges/acceptance:** disabled business loses active badge without losing its potential classification; a generic prop with a custom interaction gains the correct badge; unavailable dependencies are explained. Color is supplementary to icon/text. Badges do not steal drag gestures or overcrowd compact cards.

### U06 — Accurate animation status [S/M; P1; I06]

**Files:** metadata compiler, asset preview/details.

Display static mesh, posed mesh, rigged without clips, animated mesh, directional sprite, or animated sprite. Determine mesh status from parsed asset metadata; actual supported runtime actions are a separate list. Sprite turntable frames must not be advertised as walking animation.

**Edges/acceptance:** the three skinned SWAT models say rigged/no supplied clips, posed SWAT/K9 models remain static, and action sprites list usable loops. New asset reimport refreshes status; no inference from folder words such as “animated.”

### U07 — Character action previewer [M/L; P1/P2; I06]

Extend existing directional/frame preview controls with action selection, play/pause, timeline scrubbing, playback speed, and a facing selector. Use a consistent ground-contact marker and optional scale reference. Show missing direction coverage rather than inventing reflected asymmetric equipment.

**Edges/acceptance:** frame bounds, one-frame actions, corrupt descriptors, rapid selection switches, focus leaving the popup, no cached animation resources after closing. Preview control input never moves the editor character; scrubbing does not dirty the project.

### U08 — Scale comparison [M; P1]

Add person/car/grid references to the preview viewport; use actual prepared dimensions and a clear unit label. Provide both “fit asset” and “same scale” comparison views so large buildings do not appear equivalent to small props. Sprites use calibrated footprints rather than image pixel height as physical size.

**Edges/acceptance:** tiny satellites, broad ships, imported pivots, tall tree canopies, arbitrary object scale, mixed-mode sprite cards. The preview agrees with actual placement size, and reference objects are never saved/exported as city content.

### U09 — Style compatibility suggestions [M; P1/P2]

Rank by reviewed theme, palette family, scale, projection, and material conventions. Prefer explicit matching metadata; show “Suggested” rather than an assurance of exact fit. Allow users to include all styles and remember that choice.

**Edges/acceptance:** a sparse theme offers limited suggestions honestly; custom imports have partial metadata; a 2D item in 3D remains visibly flat. Suggestions must not force asset replacement or hide search matches needed for intentional mixed-style scenes.

### U10 — Companion-object suggestions [M; P2; I07/U02]

Create reviewed relationships such as desk→chair, pump→canopy, shelves→stock, stove→cookware. Show a small optional suggestion tray after selection/placement. “Place together” uses an assembly preview with valid anchors and cost, not instant spawning.

**Edges/acceptance:** compatible size/style, missing dependency, suggestions for a manually modified asset, duplicates already present, user dismisses tray. Placement is one undoable gesture and respects locked/protected areas and affordability.

### U11 — Visible connection affordances [L; P4; I08/N04/N05]

Show source socket, candidate target, permitted mating direction, connection type, and blocked/occupied reason while connecting. Provide keyboard next/previous target selection. Use distinct shapes/labels for power/water/structure; allow overlay toggling and avoid persistent visual clutter.

**Edges/acceptance:** occluded endpoints, overlapping floors, very small sockets, no compatible target, many candidates, colorblind mode, photo mode. Preview must show exactly the connection committed; protected targets cannot be connected through a hidden hotkey path.

### U12 — Interaction setup diagnostics [M/L; P2; I07/I14]

Add an actionable checklist for approach clearance, station capacity, required target, return route, and available action/animation. Use structured diagnostics from the actual planners, not a separate approximate UI validator.

**Edges/acceptance:** diagnostics stale after edits, hidden/locked objects, unvisited room, missing assets, several failures per station. Click a failure to frame the object/scope; do not silently switch worlds or discard an active gesture. User can safely retry after resolving the problem.

### U13 — Interior-kit chooser [M/L; P2; I13]

Show classroom, shop, apartment, workshop, and station kit previews with contents, dimensions, missing dependencies, and price/free-starter policy. Distinguish replace, add-to-room, and create-new-floor actions. Default to the least disruptive option fitting the current task.

**Edges/acceptance:** customized room, max floors, stairs/exit blocked by kit, mixed source styles, unavailable assets, insufficient funds. Replacement previews the exact affected room and is fully undoable; opening/closing chooser never creates a room prematurely.

### U14 — Recent assets by activity [S/M; P2]

Track successful placements in bounded per-task histories, not every hover. Store IDs in local preferences with a fallback to the current library. Keep the current task, query, page, and scroll position when reopening the drawer.

**Edges/acceptance:** asset removed, variant family collapsed, private/custom asset, new project/world, canceled placement. Histories are capped and do not dirty saves or synchronize to co-op peers unless deliberately added later.

### U15 — Named collections/project palettes [M/L; P2]

Add named sets of concrete asset IDs and optionally family IDs. Define whether a family member or the whole family is selected. Separate personal collections from a project's recommended palette. Palette filtering is advisory unless the user explicitly enables a content restriction.

**Edges/acceptance:** renamed/deleted assets, missing packs on another computer, duplicate collection names, import/export of collections, favorites migration, differing peer catalogs. Missing items remain identifiable and replaceable instead of being silently dropped.

### U16 — Semantic imported-asset search [M; P1; I04]

Extend existing synonyms/typo-tolerant search with reviewed semantic tags, tasks, and aliases. Keep exact names/IDs ranked first; group by intended use without changing item identity. Precompute normalized token indexes; no remote AI dependency is required.

**Edges/acceptance:** query “school chair” with words in reverse order, plurals/typos, accents, source filename lookup, filters hiding all matches. Empty results identify restrictive filters and offer a reversible broader search. Search performance measured against the full catalog.

### U17 — Library health view [M/L; P1]

Report missing/placeholder previews, unresolved metadata, atlas/reference content, invalid direction/frame definitions, and unavailable source dependencies. Separate definite defects from review suggestions; an intentionally decorative building is not automatically broken.

**Edges/acceptance:** one issue affects many variants, assets loaded lazily, source files unavailable but prepared assets usable, read-only project, interrupted repair. Preview repairs and show affected IDs before mutation; fixes are repeatable and preserve source art/legacy references.

### U18 — Small-prop editing [M; P2]

Extend overlap selection with temporary magnification, isolate-selection, focus/frame, and a clear return control for tiny kitchen/stationery/tool assets. Keep original world coordinates and avoid scaling the actual object to make it easier to click.

**Edges/acceptance:** props on shelves/counters, occluded surface, nested room, drag thresholds at high zoom, grouped objects, keyboard cursor, reset while isolated. Selection/paint protection still works; hide/isolate UI state does not accidentally change export inclusion or permanent visibility.

### U19 — Visual simulation diagnostics [L; progressive P2–P6]

Create a common diagnostic record: `{code, severity, scope, object_uid, related_uids, message_key, details, revision}`. Each subsystem supplies its own valid route/coverage/queue geometry. Provide one overlay selector and legend; combine compatible overlays only when readable.

**Edges/acceptance:** stale revision, object deleted, pending route calculation, offscreen floors, huge route collections, accessibility colors, photo mode. Selecting an issue focuses the relevant object, opens its controls, and describes the actual cause. No fake straight-line route overlays presented as verified navigation.

### U20 — Construction and rendering costs [M/L; P3/P6; I19]

Show exact economy quotes for the proposed operation and separately labeled approximate render cost. Explain instance count, expensive model-in-2D views, material/texture burden, and available lighter variants. Offer a comparison preview before replacing an asset.

**Edges/acceptance:** free starter interiors, nested copied furnishings, refund accounting, multiple shared textures, budget rejection, custom painted materials, low-detail variant changes appearance. Costs update on proposal changes, never double-charge, and do not pretend triangle count alone predicts frame rate.

## 10. Code examples

Examples below are implementation references, not claims that proposed systems already exist. Existing API calls are identified; proposed helpers need normal integration, validation, and tests. The pure helper examples are extracted and exercised by the plan verification artifact described at the end of this section.

### 10.1 Existing APIs: safely applying business overrides

This adapter follows the current `business_tools.gd` pattern. It is an integration example for a tool object that has `var studio: Control`; it is not a new method already present in Studio. `PlanExamples.business_changes` is supplied in the tested reference helper below. It plans only supported existing business fields and preserves unrelated settings.

```gdscript
# Proposed method in an editor tools class. PlanExamples is the helper below.
func apply_business_patch(patch: Dictionary) -> void:
    if studio.interior_tools.editing():
        studio.status.text = "Configure the building from the city view."
        return
    studio.finish_edit(studio.canvas_pointer())
    var items: Array = studio.selection_items() # Existing editable-selection API.
    var proposal: Dictionary = PlanExamples.business_changes(items, patch)
    if not proposal["ok"]:
        studio.status.text = proposal["reason"]
        return
    var changes: Dictionary = proposal["changes"]
    if changes.is_empty():
        studio.status.text = "Business settings are unchanged."
        return
    studio.current().checkpoint()
    for item in items:
        if changes.has(item["uid"]):
            item["business"] = changes[item["uid"]]
    studio.changed() # Existing economy/interior/co-op/dirty-state integration.
    studio.status.text = "Updated %d businesses." % changes.size()
```

Do not add `shared_authority()` as a blanket restriction on all ordinary object edits: co-op participants may edit authorized areas. Host-only financial/system operations do require authority. The host still validates protected geometry in the normal observation/acceptance flow. For a function called outside editor tools, explicitly provide equivalent transactional and protection handling.

### 10.2 Explicit metadata patches, not filename behavior guesses

The following Python example uses real catalog IDs and the existing dictionary format. It writes a review candidate, not the live catalog. After review, update the preparation/overlay source and regeneration path too.

```python
import json
from pathlib import Path

root = Path("F:/dev/IsoCity")
source = root / "resources/catalog/businesses.json"
current = json.loads(source.read_text(encoding="utf-8"))
defaults = {
    "3d:HanX_Shop/Shop_Cafe": "cafe",
    "3d:HanX_Shop/Shop_Bakery": "cafe",
    "3d:HanX_Shop/Shop_Grocery": "shop",
    "3d:HanX_Shop/Shop_Pharmacy": "shop",
}
for asset_id in defaults:
    scene = root / "scenes/items_3d" / (asset_id.removeprefix("3d:") + ".tscn")
    if not scene.is_file():
        raise ValueError(f"Missing reviewed asset: {asset_id}")
candidate = dict(current)
for asset_id, kind in defaults.items():
    if asset_id in candidate and candidate[asset_id] != kind:
        raise ValueError(f"Existing default needs explicit reconciliation: {asset_id}")
    candidate[asset_id] = kind
destination = root / "output/asset_reassessment/businesses.candidate.json"
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(candidate, indent=2) + "\n", encoding="utf-8")
```

This does not edit per-object `business` or `citizen_role` overrides. Current `BusinessPlan.profile` and `CitizenPlan.role` already define override precedence; keep their behavior and test it.

### 10.3 Adding a saved collection correctly

For a proposed `activity_sites` collection:

```gdscript
# Proposed addition in Document.valid, before trusting site records.
if value.has("activity_sites"):
    if not ActivityPlan.valid_sites(value["activity_sites"], value, library):
        return false
```

`ActivityPlan` and `valid_sites` are **new APIs to implement**, not existing preloads. Its validator must check record count, UID uniqueness, kind, schedule, scoped references, station capacity, and referenced object eligibility. Keep a pure structural validation pass plus a second reference-resolution pass.

Then add the collection to BOTH relevant lists in `document_delta.gd::between`: the `uid` identity selector and the arrays that receive indexed collection deltas. Add corresponding handling to `cooperative_plan.gd::touched/allowed`, `project_repair.gd`, copying/UID remapping, and dependency collection. Otherwise history may fall back to a large whole-field replacement and protected-area edits may bypass intended authorization.

For deletion, either remove dependent sites/edges in the same undoable transaction or retain explicitly broken references with diagnostics according to the feature contract. Do not make Undo reconstruct references from display names.

### 10.4 Pure reference algorithms

The following helper contains:

- bounded validation with finite integral JSON number handling;
- preservation of existing business settings when planning an edit;
- exclusive reservations protected against stale cancellation tokens;
- deterministic incremental breadth-first traversal with a graph revision;
- conservative integer supply allocation within one already-connected component;
- 3D socket alignment preserving requested source scale;
- stable weighted family selection.

These are deliberately small. The BFS handles unweighted connectivity only; use the existing lane/clearance graph and a weighted solver where needed. The allocator does not solve edge throughput, storage, pressure, or losses. The socket helper does not perform collision/protection checks or handle sprite projections. Every caller must enforce those higher-level constraints.

```gdscript
# Extract as: output/asset_reassessment/plan_examples.gd
extends RefCounted

const Business = preload("res://scripts/builder/business_plan.gd")

static func integral(value: Variant, low: int, high: int) -> bool:
	if not (value is int or value is float): return false
	var number: float = float(value)
	return is_finite(number) and number == floorf(number) and number >= low and number <= high

static func business_changes(items: Array, patch: Dictionary) -> Dictionary:
	for key in patch:
		if key not in ["kind", "open_hour", "close_hour", "capacity", "duration_scale"]:
			return {"ok": false, "reason": "Unsupported business setting: " + str(key)}
	if not Business.valid(patch):
		return {"ok": false, "reason": "Invalid business settings."}
	var changes: Dictionary = {}
	var seen: Dictionary = {}
	for item in items:
		if not item is Dictionary or not item.get("uid") is String:
			return {"ok": false, "reason": "Invalid selection record."}
		if item["uid"].is_empty() or seen.has(item["uid"]):
			return {"ok": false, "reason": "Duplicate or empty selection identity."}
		seen[item["uid"]] = true
		var old: Variant = item.get("business", {})
		if not old is Dictionary:
			return {"ok": false, "reason": "Repair this object's business settings first."}
		var next: Dictionary = old.duplicate(true)
		next.merge(patch, true)
		if not Business.valid(next):
			return {"ok": false, "reason": "The resulting settings are invalid."}
		if next != old: changes[item["uid"]] = next
	return {"ok": true, "changes": changes}

static func scope_key(world: String, owner: String, floor_id: String, slot: String) -> String:
	# JSON tuple avoids ambiguous separator concatenation.
	return JSON.stringify([world, owner, floor_id, slot])

class Reservations extends RefCounted:
	const MAX_CLAIMS: int = 512
	var claims: Dictionary = {}
	var next_token: int = 0

	func expire(now: float) -> void:
		if not is_finite(now): return
		for key in claims.keys():
			if float(claims[key]["expires"]) <= now: claims.erase(key)

	func reserve(slot: String, actor: String, now: float, ttl: float) -> Dictionary:
		if slot.is_empty() or slot.length() > 512 or actor.is_empty() or actor.length() > 128:
			return {"ok": false, "reason": "invalid_identity"}
		if not is_finite(now) or now < 0 or not is_finite(ttl) or ttl <= 0 or ttl > 60:
			return {"ok": false, "reason": "invalid_time"}
		expire(now)
		if claims.has(slot):
			if claims[slot]["actor"] != actor:
				return {"ok": false, "reason": "occupied"}
			claims[slot]["expires"] = now + ttl
			return {"ok": true, "claim": claims[slot].duplicate(true)}
		if claims.size() >= MAX_CLAIMS:
			return {"ok": false, "reason": "capacity"}
		next_token += 1
		claims[slot] = {"slot": slot, "actor": actor, "token": next_token, "expires": now + ttl}
		return {"ok": true, "claim": claims[slot].duplicate(true)}

	func release(slot: String, actor: String, token: int) -> bool:
		if not claims.has(slot): return false
		var claim: Dictionary = claims[slot]
		if claim["actor"] != actor or claim["token"] != token: return false
		claims.erase(slot)
		return true

	func release_actor(actor: String) -> void:
		for key in claims.keys():
			if claims[key]["actor"] == actor: claims.erase(key)

	func clear() -> void:
		claims.clear()
		# Do not reset the token counter: a delayed old release must stay stale.

class RouteSearch extends RefCounted:
	const MAX_NODES: int = 4096
	const MAX_NEIGHBORS: int = 256
	var graph: Dictionary = {}
	var revision: int = 0
	var request_id: int = 0
	var goal: String = ""
	var frontier: Array[String] = []
	var parents: Dictionary = {}
	var cursor: int = 0
	var expanded: int = 0
	var status: String = "idle"
	var path: Array[String] = []

	func begin(source: Dictionary, start: String, finish: String, graph_revision: int, id: int) -> void:
		graph = {}; frontier.clear(); parents.clear(); cursor = 0; expanded = 0; path.clear()
		revision = graph_revision; request_id = id; goal = finish; status = "invalid_graph"
		if source.size() > MAX_NODES: return
		for key in source:
			if not key is String or key.is_empty() or key.length() > 128: return
			if not source[key] is Array or source[key].size() > MAX_NEIGHBORS: return
			var neighbors: Array[String] = []
			for neighbor in source[key]:
				if not neighbor is String or not source.has(neighbor): return
				if not neighbors.has(neighbor): neighbors.append(neighbor)
			neighbors.sort()
			graph[key] = neighbors
		if not graph.has(start) or not graph.has(goal):
			status = "missing_endpoint"
			return
		frontier.append(start); parents[start] = ""; status = "pending"
		if start == goal:
			path.append(start); status = "found"

	func step(budget: int) -> Dictionary:
		var spent: int = 0
		while status == "pending" and cursor < frontier.size() and spent < clampi(budget, 0, 128):
			var node: String = frontier[cursor]
			cursor += 1; spent += 1; expanded += 1
			for neighbor in graph[node]:
				if parents.has(neighbor): continue
				parents[neighbor] = node; frontier.append(neighbor)
				if neighbor == goal:
					var at: String = goal
					while not at.is_empty():
						path.push_front(at); at = parents[at]
					status = "found"
					break
		if status == "pending" and cursor >= frontier.size(): status = "unreachable"
		return {"status": status, "path": path.duplicate(), "revision": revision,
			"request_id": request_id, "expanded": expanded, "spent": spent}

static func allocate_component(supply: Variant, consumers: Array) -> Dictionary:
	# One already-connected component; no edge capacities or storage in this helper.
	if not integral(supply, 0, 1000000000) or consumers.size() > 4096:
		return {"ok": false, "reason": "invalid_capacity"}
	var seen: Dictionary = {}
	var ordered: Array[Dictionary] = []
	for item in consumers:
		if not item is Dictionary or not item.get("uid") is String:
			return {"ok": false, "reason": "invalid_consumer"}
		var uid: String = item["uid"]
		if uid.is_empty() or uid.length() > 128 or seen.has(uid):
			return {"ok": false, "reason": "duplicate_or_invalid_uid"}
		if not integral(item.get("demand"), 0, 1000000) or not integral(item.get("priority", 0), 0, 100):
			return {"ok": false, "reason": "invalid_demand"}
		seen[uid] = true
		ordered.append({"uid": uid, "demand": int(item["demand"]), "priority": int(item.get("priority", 0))})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["priority"] > b["priority"] if a["priority"] != b["priority"] else a["uid"] < b["uid"])
	var remaining: int = int(supply)
	var allocations: Dictionary = {}
	for consumer in ordered:
		var amount: int = mini(remaining, consumer["demand"])
		allocations[consumer["uid"]] = amount
		remaining -= amount
	return {"ok": true, "allocations": allocations, "used": int(supply) - remaining, "unused": remaining}

static func finite_transform(value: Transform3D) -> bool:
	for vector in [value.origin, value.basis.x, value.basis.y, value.basis.z]:
		if not is_finite(vector.x) or not is_finite(vector.y) or not is_finite(vector.z): return false
	return true

static func socket_transform(target_world: Transform3D, source_local: Transform3D, source_scale: float) -> Dictionary:
	if not finite_transform(target_world) or not finite_transform(source_local):
		return {"ok": false, "reason": "nonfinite_transform"}
	if not is_finite(source_scale) or source_scale < .1 or source_scale > 8:
		return {"ok": false, "reason": "invalid_scale"}
	# Mirrored/singular target bases need a separately designed policy.
	if target_world.basis.determinant() <= .000001:
		return {"ok": false, "reason": "invalid_target_basis"}
	var source_basis: Basis = source_local.basis
	if source_basis.determinant() < .999 or not source_basis.is_equal_approx(source_basis.orthonormalized()):
		return {"ok": false, "reason": "source_socket_must_be_rotation"}
	var target_basis: Basis = target_world.basis.orthonormalized()
	# Sockets use local +Z outward and +Y up; mating flips the outward normal.
	var desired: Basis = target_basis * Basis(Vector3.UP, PI)
	var rotation: Basis = desired * source_basis.inverse()
	var scaled: Basis = rotation.scaled(Vector3.ONE * source_scale)
	var origin: Vector3 = target_world.origin - scaled * source_local.origin
	return {"ok": true, "transform": Transform3D(scaled, origin)}

static func weighted_family(weights: Dictionary, seed_value: int) -> String:
	var ids: Array = weights.keys()
	var total: int = 0
	for id in ids:
		if not id is String or not integral(weights[id], 0, 1000000): return ""
		total += int(weights[id])
		if total > 1000000000: return ""
	if total == 0: return ""
	ids.sort()
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var choice: int = random.randi_range(0, total - 1)
	for id in ids:
		choice -= int(weights[id])
		if choice < 0: return id
	return ""

```

### 10.5 Executable test harness

This harness tests the reference algorithms and their interaction with the actual `Document` and `FloorDocument` APIs. It does not implement or certify the 60 proposed features.

```gdscript
# Extract as: output/asset_reassessment/test_plan_examples.gd
extends SceneTree

const Examples = preload("res://output/asset_reassessment/plan_examples.gd")
const Document = preload("res://scripts/builder/document.gd")
const FloorDocument = preload("res://scripts/builder/floor_document.gd")
const Delta = preload("res://scripts/builder/document_delta.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for value in [0, 1, 2.0, 100]: check(Examples.integral(value, 0, 100), "Finite integer accepted")
	for value in [-1, 101, 1.5, true, "2", NAN, INF, null]: check(not Examples.integral(value, 0, 100), "Invalid count rejected")
	var source: Array = [{"uid": "cafe", "business": {"kind": "cafe", "capacity": 4, "extension": {"note": "keep"}}}]
	var original: Array = source.duplicate(true)
	var proposal: Dictionary = Examples.business_changes(source, {"capacity": 2})
	check(proposal["ok"] and proposal["changes"]["cafe"]["extension"]["note"] == "keep", "Business patch preserves extensions")
	check(source == original, "Planning never mutates inputs")
	check(Examples.business_changes(source, {"capacity": 4})["changes"].is_empty(), "No-op avoids history")
	check(not Examples.business_changes(source, {"capacity": 2.5})["ok"], "Fractional capacity rejected")
	check(not Examples.business_changes(source, {"unknown": 2})["ok"], "Unsupported edit field rejected")
	check(not Examples.business_changes([source[0], source[0]], {"capacity": 2})["ok"], "Duplicate selection UID rejected")
	check(not Examples.business_changes([{"uid": "", "business": {}}], {"capacity": 2})["ok"], "Empty selection UID rejected")
	check(Examples.business_changes(source, {"kind": "none"})["changes"]["cafe"]["kind"] == "none", "Explicit opt-out retained")
	var doc = Document.new()
	doc.data = {"title": "Fixture", "mode": "2d", "objects": source.duplicate(true), "tiles": [], "night": false}
	var before: Dictionary = doc.data.duplicate(true)
	doc.checkpoint(); doc.data["objects"][0]["business"] = proposal["changes"]["cafe"].duplicate(true); doc.finish_checkpoint()
	check(doc.undo_history.size() == 1 and doc.undo(), "One real Document history gesture")
	check(doc.data == before, "Real Document undo restores original")
	check(doc.redo() and doc.data["objects"][0]["business"]["capacity"] == 2, "Real Document redo restores patch")
	var owned = FloorDocument.new()
	owned.configure({"title": "Ground", "mode": "2d", "objects": [], "tiles": [], "night": false, "floor_name": "Ground",
		"floors": [{"uid": "upper", "name": "Upper", "height": 3, "room": {"title": "Upper", "mode": "2d", "interior_room": true, "objects": source.duplicate(true), "tiles": [], "night": false}}]})
	check(owned.switch_floor("upper"), "Switch to real canonical floor adapter")
	owned.checkpoint(); owned.data["objects"][0]["business"]["capacity"] = 2; owned.finish_checkpoint()
	owned.switch_floor("ground")
	check(owned.undo() and owned.floor_uid == "upper" and owned.data["objects"][0]["business"]["capacity"] == 4, "Floor undo follows canonical edit and floor")
	check(owned.redo() and owned.data["objects"][0]["business"]["capacity"] == 2, "Canonical floor redo")
	var reservation = Examples.Reservations.new()
	var slot: String = Examples.scope_key("2d", "house", "upper", "chair")
	check(slot != Examples.scope_key("3d", "house", "upper", "chair"), "World scopes differ")
	var first: Dictionary = reservation.reserve(slot, "a", 0, 5)
	check(first["ok"] and not reservation.reserve(slot, "b", 1, 5)["ok"], "Seat cannot be double-booked")
	check(reservation.reserve(slot, "a", 1, 5)["claim"]["token"] == first["claim"]["token"], "Renewal retains active claim")
	first["claim"]["actor"] = "outside mutation"
	check(reservation.claims[slot]["actor"] == "a", "Returned claims are copies")
	var old_token: int = reservation.claims[slot]["token"]
	var replacement: Dictionary = reservation.reserve(slot, "b", 6, 5)
	check(replacement["ok"] and replacement["claim"]["token"] != old_token, "Expired claim is replaced at boundary")
	check(not reservation.release(slot, "a", old_token) and reservation.claims.has(slot), "Stale cancellation cannot remove new claimant")
	check(not reservation.reserve(slot, "b", NAN, 5)["ok"], "Invalid reservation clock rejected")
	reservation.release_actor("b"); check(reservation.claims.is_empty(), "Actor cleanup releases reservations")
	var fresh: Dictionary = reservation.reserve(slot, "a", 7, 5); reservation.clear()
	check(reservation.reserve(slot, "a", 8, 5)["claim"]["token"] > fresh["claim"]["token"], "Clear does not reuse tokens")
	reservation.clear()
	for index in reservation.MAX_CLAIMS: reservation.reserve(str(index), "a", 0, 5)
	check(not reservation.reserve("overflow", "a", 0, 5)["ok"], "Reservation count is bounded")
	reservation.expire(5); check(reservation.claims.is_empty(), "All expired claims released at boundary")
	var route = Examples.RouteSearch.new()
	var graph: Dictionary = {"a": ["c", "b"], "b": ["d"], "c": ["d"], "d": [], "isolated": []}
	route.begin(graph, "a", "d", 7, 19)
	check(route.step(0)["status"] == "pending", "Zero budget does no route work")
	var step: Dictionary = route.step(1)
	check(step["status"] == "pending" and step["spent"] == 1, "Route budget respected")
	step = route.step(1)
	check(step["status"] == "found" and step["path"] == ["a", "b", "d"], "Stable neighbor ordering selects deterministic path")
	check(step["revision"] == 7 and step["request_id"] == 19, "Result retains revision and request identity")
	step["path"].clear(); check(not route.path.is_empty(), "Route result cannot mutate cached path")
	route.begin(graph, "a", "isolated", 8, 20)
	while route.status == "pending": route.step(1)
	check(route.status == "unreachable" and route.expanded <= graph.size(), "Disconnected route terminates")
	route.begin(graph, "a", "a", 8, 21); check(route.path == ["a"], "Same endpoint route is valid")
	route.begin(graph, "missing", "a", 8, 22); check(route.status == "missing_endpoint", "Missing route endpoint explicit")
	route.begin({"a": ["unknown"]}, "a", "a", 9, 23); check(route.status == "invalid_graph", "Dangling graph edge rejected")
	route.begin({"a": ["b"], "b": ["a"], "c": []}, "a", "c", 10, 24)
	while route.status == "pending": route.step(1)
	check(route.status == "unreachable" and route.expanded == 2, "Cyclic route graph terminates without repeated expansion")
	var demands: Array = [{"uid": "b", "demand": 5, "priority": 0}, {"uid": "a", "demand": 4, "priority": 1}]
	var allocation: Dictionary = Examples.allocate_component(6, demands)
	check(allocation["ok"] and allocation["allocations"] == {"a": 4, "b": 2}, "Priority allocation deterministic")
	check(allocation["used"] + allocation["unused"] == 6, "Supply conserved")
	check(Examples.allocate_component(0, demands)["used"] == 0, "No supply creates no output")
	check(Examples.allocate_component(20, demands)["unused"] == 11, "Excess is retained for caller")
	check(not Examples.allocate_component(1, [{"uid": "a", "demand": 1}, {"uid": "a", "demand": 1}])["ok"], "Duplicate demand IDs rejected")
	check(not Examples.allocate_component(1, [{"uid": "a", "demand": NAN}])["ok"], "Nonfinite demand rejected")
	var reversed: Array = demands.duplicate(true); reversed.reverse()
	check(Examples.allocate_component(6, reversed) == allocation, "Allocation independent of input order")
	var target := Transform3D(Basis(Vector3.UP, .7).scaled(Vector3.ONE * 2), Vector3(3, 4, 5))
	var local := Transform3D(Basis(Vector3.UP, .3), Vector3(2, 0, 1))
	var solution: Dictionary = Examples.socket_transform(target, local, 1.5)
	check(solution["ok"], "Scaled connector solution exists")
	var solved: Transform3D = solution["transform"]
	check((solved * local.origin).is_equal_approx(target.origin), "Connector origins coincide")
	check((solved.basis * local.basis.z).normalized().dot(target.basis.z.normalized()) < -.999, "Connector normals oppose")
	check(is_equal_approx(solved.basis.x.length(), 1.5), "Source scale retained")
	check(not Examples.socket_transform(target, local, 0)["ok"], "Zero source scale rejected")
	check(not Examples.socket_transform(Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO), local, 1)["ok"], "Singular target rejected")
	for seed_value in 20:
		check(Examples.weighted_family({"a": 1, "b": 2}, seed_value) == Examples.weighted_family({"b": 2, "a": 1}, seed_value), "Seeded choice ignores dictionary insertion order")
	check(Examples.weighted_family({"a": 0}, 1).is_empty(), "Empty weighted pool handled")
	check(Examples.weighted_family({"a": 1.5}, 1).is_empty(), "Invalid weight rejected")
	check(Examples.weighted_family({"a": 1, 2: 1}, 1).is_empty(), "Mixed-type IDs rejected before sorting")
	print("PLAN EXAMPLES: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

```

At this planning checkpoint, these examples passed **83 checks, 0 failures** under Godot 4.7.1. The editor adapter in section 10.1 is an integration sketch using existing methods; it was not exercised as a live UI command. The Python candidate-generation example in section 10.2 is included for review and was not applied to the live catalog.

### 10.6 Integrating the reference helpers without introducing hidden bugs

**Reservations:** use a monotonic simulation-seconds clock per runtime session, not a daily hour that wraps at midnight. Pause expiry with the same policy as the activity. Renew only while the actor is still valid and proceeding; explicitly release on cancellation, deletion, scope change, and shutdown. A timeout is a final leak guard, not the normal completion path. Capacity greater than one uses separately identified slots or a capacity-aware extension. The helper reserves exclusive slots and does not solve queue fairness. Add FIFO/age policy in the scheduler.

**Routes:** the helper validates/copies its small graph at `begin`; production should build a validated immutable graph once per revision, not clone a potentially million-edge graph for each actor. `step` caps node expansions, not elapsed milliseconds; combine this with a measured total scheduler time budget and per-frame round-robin fairness. Accept a result only if both `request_id` and `revision` match the actor's current request. A found path still needs lane turns, traveler width, terrain, docking, and dynamic-obstacle checks before use.

**Utility allocation:** `allocate_component` accepts only consumers already known to be connected to that component. Call once per disjoint component with each source counted once. Consumers are deterministically ordered by priority then ID; starvation of low-priority demand is an explicit initial policy, not fair sharing. If fairness is desired, add a documented rotating/weighted policy with persisted or reproducible tie state. Never run the same producer independently for every consumer. Account for storage in one authoritative balance update outside this helper.

**Sockets:** `source_local` must be a rotation-only local frame with its source-space position. `target_world` contains its actual world position and orientation; the helper removes target scale from orientation and retains the chosen uniform source scale. It rejects mirrored/singular target bases and non-rotation source frames. Add explicit target shear/nonuniform-scale policy before allowing such transforms. Validate connector kind/diameter, collision, protection, and occupied sockets separately. Do not write a 3D transform directly into saved 2D sprite coordinates.

**Random choice:** the helper weights base family IDs, not palette variants. It is deterministic for the same engine/RNG behavior, inputs, and seed. For saved procedural content, persist the actual chosen IDs/proposal and catalog revision; do not promise cross-engine-version reproducibility solely from a seed.

### 10.7 Activity transaction algorithm

Use this order for persistent stock/rewards; it is an algorithm contract rather than an already-existing API:

1. Resolve the authoritative scope and verify the job is still active at the expected revision.
2. Validate the arrival/interaction conditions from actual runtime state.
3. Build a receipt key from stable job UID + completion sequence; check it against the authoritative account's bounded receipt ledger.
4. Prepare a candidate update containing input consumption, output addition, stock changes, reward/charge, receipt, and job terminal state.
5. Validate all capacities and balances on the candidate. Apply no partial effect when validation fails.
6. Commit the candidate through the appropriate authored/progress transaction path, then update presentation.
7. Persist receipt and account together using atomic project storage when the feature promises persistence.
8. Release reserved resources after terminal state is committed; a retry reads the receipt and returns the prior result.

If job state resets on reload but money persists, resetting receipts would permit duplicate rewards. Either persist the progress/receipt contract with the account or keep the entire activity economy in an independent runtime session. For Studio preview, choose a clearly labeled simulation account unless the user has deliberately enabled persistent gameplay progression. Do not award persistent funds from mere playback, camera time jumps, or editor preview restarts.

### 10.8 ID remapping for assemblies and copied facilities

Before mutating the destination, enumerate all copied identities: outer objects, nested objects, floors, floor links, entrances, sites, stations, utility edges, jobs/proposals that are intentionally authored, and groups. Generate one old-scoped-ID → new-scoped-ID mapping. Copy records, then resolve internal references through that mapping. Preserve external references only if the assembly format explicitly declares them as required connection points; otherwise leave a diagnosed unresolved socket.

Do not change referenced catalog asset IDs; those describe reusable source art. Do not serialize runtime reservations or in-progress actor nodes into an assembly. A duplicate building receives independent room/site state and no inherited live visitor claims. A copied recipe definition may be shared read-only; its stock/account state may not alias the original dictionary.

## 11. Verification and performance

### 11.1 Baseline commands

Use PowerShell from the repository. Resolve the engine from PATH or the existing wrapper; no engine install is necessary on this machine.

```powershell
Set-Location -LiteralPath 'F:\dev\IsoCity'
Get-Command godot_console
godot_console --version

# Reference examples embedded above; these files exist in this planning workspace.
godot_console --headless --path . --script res://output/asset_reassessment/test_plan_examples.gd -- --test

# Existing focused suites: select the ones affected by your change.
godot_console --headless --path . --script res://tools/test_business_plan.gd -- --test
godot_console --headless --path . --script res://tools/test_supplemental_assets.gd -- --test
godot_console --headless --path . --script res://tools/test_consumer_ui.gd -- --consumer-ui

# Existing complete verification wrapper, once a milestone warrants it.
python tools/verify_scenes.py
```

The full verification wrapper was **not** run for this documentation task. Only the reference-code checks and document consistency checks were run. Do not copy older verification totals from `IMPLEMENTATION.md` as proof of a newly changed feature.

To regenerate the example files in a separate checkout, save each fenced block starting `# Extract as:` to its named repository-relative file. They are embedded in this plan so the ignored `output/` artifacts are not required for reproducibility. Ensure the test helper preload remains pointed at the extracted helper location.

Before real-world integration tests, use `--test` where the suite supports it and follow existing fixtures' storage-root overrides. Never point recovery/creation tests at the user's actual projects or gallery folders. Use bounded temporary paths under `output/verification/<feature>/`. Do not launch multiple import processes against one `.godot` cache.

### 11.2 Test layers

1. **Pure plan:** malformed data, normalization, deterministic output, graph constraints, quotas, receipts, bounds. No scene tree required beyond the SceneTree test runner.
2. **Document integration:** history, extensions, preservation of unknown unrelated fields, nested floors, economy quote/rollback, save/load, recovery, duplication/remapping.
3. **Actual runtime:** real physics frames, collisions, actors, queues, cancellation, pause/resume, transitions, teardown. Assert behavior, not merely node count.
4. **Editor workflow:** command dispatch, simple/precision UI, pointer hit-testing, keyboard alternatives, mixed selection, protected/hidden content, no-op history, dirty state.
5. **Export generation:** enumerate all direct and future dependencies, catalog subset, prepared assets, scripts, source JSON, and existing restriction errors.
6. **Fresh export runtime:** extract to a clean folder, import, launch, exercise the feature without referencing the original checkout. Test permitted-content and intentionally blocked-content cases separately.
7. **Visual/audio review:** actual renderer captures at desktop and 960×640; inspect geometry/overlap/typography; listen to audio when it changes. Headless success cannot establish visual quality.

### 11.3 Existing regression entry points by area

| Change area | Existing tests to consider | New focused tests to add when implementing |
|---|---|---|
| Catalog/families/previews | `test_all_assets.gd`, `test_added_assets.gd`, `test_supplemental_assets.gd`, `test_swat_pack.gd`, `test_asset_browser.gd` | family membership/defaults, variant reachability, preview non-placeholder fixtures, semantic search corpus |
| Anchors/modular geometry | `test_library_grid.gd`, `test_alignment.gd`, `test_arrange_tools.gd`, `test_entrance_anchors.gd`, `test_transform_handles.gd` | socket compatibility, scaled/rotated mating, room outline synthesis, protected target |
| Business/activities | `test_business_plan.gd`, `test_business_runtime.gd`, `test_props_foundation.gd`, `test_props_workflow.gd` | activity plan/runtime/workflow/export, reservation contention, transactional recipe/order completion |
| Citizens/interiors | `test_citizen_runtime.gd`, `test_citizen_neighborhood.gd`, `test_persistent_interiors.gd`, `test_floor_nested_history.gd`, `test_floor_editor_walk.gd` | scoped itinerary transitions, offscreen occupancy, building/floor deletion, independent copied rooms |
| Roads/fleets | `test_traffic_plan.gd`, `test_traffic_runtime.gd`, `test_transit_runtime.gd`, `test_service_runtime.gd`, `test_driving_workflow.gd` | signals, vehicle dimensions, graph-revision reroute, dock/rack access |
| Terrain/water | `test_terrain_navigation.gd`, `test_terrain_roads.gd`, `test_terrain_traffic.gd`, `test_terrain_transit.gd`, `test_terrain_services.gd` | shore topology masks, flood/grade rerouting, navigable-water vessel clearance |
| Economy/zoning/blueprints | `test_economy_plan.gd`, `test_zone_plan.gd`, `test_neighborhood_plan.gd`, `test_blueprint_foundation.gd` | family-level probabilities, complete assembly quote, idempotent receipts, utilities conservation |
| Recovery/co-op | `test_project_repair.gd`, `test_project_recovery.gd`, `test_cooperative_protection.gd`, `test_cooperative_workflow.gd`, `test_cooperative_peer.gd` | every new array's protected-area policy, malformed references, host charges once, late rejected edits |
| UI/accessibility | `test_consumer_ui.gd`, `test_control_settings.gd`, `test_accessibility.gd`, `test_workspace_layout.gd`, `test_overlap_picker.gd` | new drawer navigation, keyboard socket picker, tiny-prop isolation, filter combinations |
| Audio/performance | `test_ambience_runtime.gd`, `test_ambience_workflow.gd`, affected runtime suites | voice caps/context crossfades, cache eviction counters, actor/node/resource teardown |
| Portable/runtime | relevant `test_*_export_runtime.gd`, `verify_*_portable.py`, `test_portable_export.gd` | standalone fresh fixtures for every new enabled runtime and future dependency |

The last column names test responsibilities, not pre-existing files. Name new suites consistently (`test_school_plan.gd`, `test_school_runtime.gd`, etc.) and register only real implemented suites in the wrapper. Use the existing SceneTree `check`/failure-counter pattern to accumulate useful assertions and return nonzero on failure.

### 11.4 Minimum edge-case matrix

Each feature should mark rows relevant/not applicable with a reason; do not blindly multiply every possible combination for a data-only label change.

| Dimension | Cases |
|---|---|
| Document/view | Pixel city, 3D city; sprite-in-3D and model-in-2D where supported; exterior, ground room, upper floor |
| Transform | default, 90° turn, arbitrary yaw, allowed pitch/roll, minimum/maximum supported scale, source-view change |
| Lifecycle | first creation, repeated configure, normal completion, cancel at each stage, delete target, Undo target deletion, reset, load another project, close |
| Time | paused, resumed, inactive world, interior visit, zero delta, negative/nonfinite delta, bounded long frame, midnight, explicit time jump |
| State | settings absent, default disabled, enabled, custom override, explicit opt-out, unknown unrelated extension |
| Geometry | clear, blocked entrance, narrow passage, steep ground, water, missing road, occupied bay/seat, incompatible socket |
| Identity | duplicate UID, dangling reference, duplicate building/floor, same UID in a different scope, stale async result |
| Economy | off, sufficient funds, exact funds, insufficient funds, free starter content, demolition/refund, repeated completion receipt |
| Collaboration | host, permitted participant, protected region, conflicting later edit, disconnect before acceptance, new dependencies unavailable to peer |
| Availability | missing source asset, prepared source available without original archive, missing preview, disabled layer, hidden object, locked object |
| Persistence | save/open, Save As, autosave/recovery, repair, allowed export, intentionally disallowed export, clean portable import |
| UI | mouse, keyboard/remapped controls, large text/high contrast, 960×640, photo/focus mode, overlay above canvas |

### 11.5 Golden scenarios and assets

Build versioned fixtures with small deterministic documents and explicit seeds. Keep them source-controlled under a new `tools/fixtures/asset_expansion/` directory rather than only as generated output. Include JSON schemas/version notes and regenerate screenshots separately.

1. **Modern block:** homes, one HanX café, grocery, school, gas station, four-way junction, bus stops, service station. Exercises I01/I10–I16 and N01–N03/N07.
2. **Interior activity floor:** classroom, two seats, counter, washer/dryer, kitchen, and stairs/elevator to a second floor. Exercises reservations, scope, nested history, and interrupted work.
3. **Utility shortage:** two disconnected networks, one source each, prioritized consumers, and optional storage. Exercises disconnection, deterministic allocation, conservation, and reconnect.
4. **Construction site:** protected boundary, material drop-off, scaffold/frame, and one complete blueprint assembly. Exercises cost, connections, copying, co-op conflict, and stage cleanup.
5. **Waterfront:** simple connected water, island/obstacle, two docks, one vessel, safe boarding/exit. Exercises water edits and blocked docking.
6. **Space outpost:** one modular room, dock, supplied ship, and supply contract. Keep assets explicitly allowed for the export fixture.

Do not require all 6,233 assets in every regression fixture. A catalog-specific audit should check the whole inventory; runtime fixtures should select representative worst cases and all declared supported behaviors.

### 11.6 Performance measurement protocol

Record engine version, renderer, hardware, resolution, asset counts, actor counts, active systems, and whether capture/profiling is enabled. Capture cold startup and warm steady-state separately. Use the same camera and seed for before/after comparisons. Report median and p95 frame times, memory/cache sizes, active nodes/voices, route expansions, graph rebuilds, and thumbnail generation latency.

Proposed engineering targets, to calibrate against this machine rather than assert as achieved:

- No repeated full catalog scan in a per-frame UI path. Search/filter results may be cached by query/filter/catalog revision.
- No world-wide topology rebuild for a color-only edit; record invalidation reasons.
- Shared routing/utility planning should use a measured per-frame time budget; begin with a 2 ms total planning budget in interactive scenes and adapt from evidence.
- Pending work, actors, cache entries, and history remain bounded; repeated enter/leave/reconfigure cycles return to a stable resource baseline.
- A 60 Hz target means a 16.7 ms total frame budget, but supported hardware/settings determine whether that is achievable. Never sacrifice correct collision/history for a numerical claim.
- Stress within current road/population/floor limits first. Raising limits is a separately measured schema/performance change, not a hidden side effect of adding more assets.

Test small and medium scenes for correctness, then one stress fixture for the changed subsystem. Broaden once when integration warrants it; do not rerun the complete asset suite after every text adjustment. Rendering optimizations must preserve custom materials, selected overlays, interactive nodes, and exported collisions.

### 11.7 Definition of done

A ticket is complete only when:

- Its visible behavior and acceptance criteria work, not just its schema or panel.
- Saved data is validated/repaired, old documents still load, and custom overrides survive.
- Relevant Undo/Redo, economy, duplication, nested-room, co-op, and export paths pass.
- Runtime actors/reservations/resources clean up on cancel, deletion, world/floor switch, reset, and shutdown.
- Commands are discoverable through the appropriate simple/precision surfaces and accessible controls.
- Supporting assets/audio/animations really exist; remaining fallbacks are explicit and within the promised scope.
- Evidence lists exact commands, observed results, fixture paths, and rendered captures where applicable.
- Documentation describes behavior and limits accurately. No pending substep is hidden behind a checked checkbox.

## 12. Implementation-agent handoff

### 12.1 Start-of-task procedure

1. Read this plan, any applicable `AGENTS.md`, current `README.md`, and the relevant current source. The audit is a checkpoint, not permission to overwrite newer changes.
2. Inspect workspace changes and preserve the user's work. Use the existing checkout unless instructed otherwise. No sub-agent delegation is required by this plan.
3. Select one ticket or tightly coupled slice and write a concrete acceptance fixture before broad refactoring.
4. Revalidate referenced asset IDs in the current library. Do not guess hash suffixes or infer capabilities from pack names.
5. Trace the full saved-data/runtime/export path for that slice. Extend existing modules before creating parallel managers.
6. Implement pure rules, then runtime behavior, then editor commands/UI, then persistence/export/co-op integration.
7. Run focused tests, inspect actual rendered results for visual changes, then the affected regression/portable checks.
8. Update a new implementation tracker with evidence and remaining substeps. Do not alter older historical completion claims to imply this backlog was already done.

### 12.2 Suggested new tracker format

Create `ASSET_EXPANSION_PROGRESS.md` when implementation starts; it is not necessary to create 60 fake completed entries now.

```markdown
## I05 — Preview repair
Status: in progress
Implemented: active model preview generation and full-detail GIF fallback.
Remaining: cropped-preview regression fixture; consumer drawer visual review.
Changed files: ...
Validation: exact command, exit status, relevant assertions, renderer used.
Evidence: output/verification/I05/...
Compatibility: IDs unchanged; old saves tested; export dependencies tested.
Known limits: ...
Next task: ...
```

Keep proposed/new file lists in ticket notes until files actually exist. A future agent should be able to see which tests were run and which were only planned. If scope changes, update the ticket and dependency notes instead of silently redefining “done.”

### 12.3 High-risk integration pitfalls

| Pitfall | Prevention |
|---|---|
| Generated catalog edit disappears on regeneration | Modify generator inputs/explicit overlay and test idempotent rebuild. |
| New tag accidentally enables gameplay on every old placement | Separate descriptive metadata from default behavior; version material changes and preserve opt-outs. |
| Palette variants overwhelm generation probabilities | Weight families, choose appearance second. |
| New setting validates in editor but disappears on repair/export | Follow the schema checklist across all entry points and portable subset generation. |
| Floor edit changes wrong document/history | Use `FloorDocument`/`interior_tools`; test from upper floor and through exterior Undo. |
| Failed budget leaves half-built content | Prepare and quote the whole candidate; commit atomically; remap references before acceptance. |
| Queues/supply duplicate after reload | Explicit persistence contract; persistent receipts with persistent funds; transient state resets together. |
| Late route result moves a deleted or reconfigured actor | Compare request ID, graph revision, scope, and actor existence before applying. |
| UI is smooth but hides incorrect functionality | Require actual travel, interaction, stock, or scoring assertions; static screenshots alone do not prove gameplay. |
| GPU cleanup overlooked in mixed model/sprite view | Track viewports/textures/actors over repeated create/delete/scope switches. |
| Export succeeds only in original checkout | Fresh extraction/import/run with no source-project path fallback. |
| Asset restrictions silently bypassed | Preserve existing metadata checks and test the error path as a valid result for restricted dependencies. |
| Assuming co-op means shared live simulation | Keep authoring versus runtime authority explicit; add a separate protocol only if deliberately implementing synchronized play. |
| A new action hijacks remapped keys or canvas painting | Register through current controls/commands and preserve focus/hit-test rules. |
| Overgeneralizing the first activity into a huge framework | Ship one full example, extract only proven shared pieces, then add the next domain. |

### 12.4 Exact asset-ID starter references

These IDs were verified in the current catalog. They are examples, not a complete support list. Respect their source mode and capabilities; sprites placed in a 3D document remain sprites.

| Use | Exact ID |
|---|---|
| Café | `3d:HanX_Shop/Shop_Cafe` |
| School | `3d:HanX_School/School_Building` |
| EV charger | `3d:HanX_GasStation/EV_Charger` |
| Construction excavator | `3d:HanX_Construction/Excavator` |
| Bicycle | `3d:HanX_Traffic/Bicycle` |
| Student desk sprite | `2d:Supplemental_Classroom_school_kit_student_desk_5d5a19f2` |
| Greenhouse | `2d:Supplemental_Garden_greenhouse_kit_greenhouse_814e7d66` |
| Raised bed | `2d:Supplemental_Garden_greenhouse_kit_raised_bed_39ed9dc1` |
| Treadmill | `2d:Supplemental_Gym_fitness_kit_treadmill_4ecc12e0` |
| Cutting board | `2d:Supplemental_Kitchen_cookware_kit_cutting_board_6ebd69ca` |
| Industrial washer | `2d:Supplemental_Laundromat_kit_industrial_washer_29a09cf7` |
| Folding table | `2d:Supplemental_Laundromat_kit_folding_table_3b3f1c1f` |
| Dome tent | `2d:Supplemental_Camping_gear_kit_dome_tent_ae1e2dc1` |
| Campfire | `2d:Supplemental_Camping_gear_kit_campfire_e8155646` |
| Village windmill | `2d:Supplemental_Village_buildings_windmill_nopalette_studio_99dcf443` |
| Village bakery | `2d:Supplemental_Village_buildings_bakery_nopalette_studio_52216265` |
| Water tower | `2d:Supplemental_Water_towers_classic_spheroid_nopalette_studio_1e706cb4` |
| Solar plant sprite | `2d:Added_rendered_power_plants_solar_pv_ef87763b` |
| Substation sprite | `2d:Added_rendered_electrical_substation_electrical_substation_6b41edc6` |
| Spaceships II example | `3d:Supplemental_Spaceships_II/belly_bay_bomber` |

### 12.5 Decisions already made versus decisions to resolve during implementation

**Defaults set by this plan:** stable IDs; optional new simulation; explicit behavior metadata; per-scope references; existing history/economy/co-op protection preserved; complete portable dependency handling; simple shell retained; no automatic conversion of sprite art to meshes; no promise that a rig includes clips; source files preserved.

**Resolve through the first tested slice:** final site/network schema bounds; exact timing and rewards; which assets receive reviewed functional defaults; authoring UX for connectors; how offscreen interior schedules coexist with today's exterior pause policy; which animation gaps require new art; whether a domain's progress is transient or persistent. Record the decision in the implementation tracker and tests. Ask the user only for product choices that materially change their requested scope; routine implementation choices can be settled from current architecture and evidence.

**Do not silently add:** internet matchmaking, user accounts, cloud services, external purchases, arbitrary downloaded-script execution, physically accurate engineering simulations, or a replacement game engine. None is required to implement this asset-informed plan.
