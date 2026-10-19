# Nervegear project roadmap

**Status:** N0.1–N0.3 and N1 implemented; player meadow playtest pending
**Platform:** macOS native desktop
**Source of world canon:** `../aincrad2`
**First playable region:** Floor 1
**Primary priorities:** Iteration speed → visual identity → ecological simulation → world expansion

## Vision

Nervegear is a native graphical world for Aincrad2. You play in a small, walkable section of Floor 1, viewed through a close third-person camera.

Its first objective is not to recreate Aincrad2's RPG systems. It is to make a small section of Floor 1 feel alive.

The player should be able to watch weather change, observe vegetation responding to soil and light, see animals alter their surroundings, and modify the environment while the consequences unfold over time.

The first milestone is a pleasant meadow that you can explore on foot.

### Non-goals

- No gameplay mechanics port from Aincrad2 yet.
- No combat, quests, inventories, skill systems, or NPC dialogue.
- No multiplayer or server integration.
- No mobile, browser, or cross-platform implementation.
- No enormous procedurally generated world.
- No proprietary game engine.
- No attempt at photorealism.
- No generalized ECS or elaborate engine framework.
- No wholesale port of Meadowlight.
- No sophisticated player-facing UI before a world worth displaying exists.

Preserve clean boundaries that make future integration possible, without implementing speculative extensibility.

---

## N0: The development loop

**Priority: Absolute. Complete before working on ecological simulation or game content.**

### N0.1: Native application and player

Create a fresh repository `nervegear` using SwiftPM, Swift 6.4, AppKit, MetalKit and Metal Shading Language.

Create a native resizable window with an `MTKView` containing:

- A perspective camera that follows a visible player from close behind.
- Player movement through the meadow with WASD and a game controller.
- A simple walking animation.
- A grass meadow with wildflowers and gently uneven terrain.
- Depth testing, directional lighting and shadows.
- Mouse and controller camera orbit, plus scroll-wheel zoom.

Do not add an editor, HUD, console, inspector, asset database, runtime ECS or general scene graph.

Prefer a small number of self-contained components over a deep package hierarchy.

### N0.2: Build profiles

Keep the `dev`, `dev-fast` and `release` build commands.

| Profile | Purpose |
|---|---|
| `dev` | Debug build without DWARF debug information |
| `dev-fast` | Optimized debug build with assertions |
| `release` | Optimized release build |

Use `-Onone -gnone` for `dev` and `-O` without whole-module optimization for `dev-fast`.

Keep assertions and useful error diagnostics. Do not use unchecked optimization in the development profiles. A plain SwiftPM debug build remains available for symbolic debugging.

### N0.3: Hot reload

Keep file reloads for shaders, scenes and materials:

**Shader edits**

Watch `.metal` files and compile replacements away from the render loop. Switch validated pipelines at a frame boundary. A failed compile keeps the running shader and writes an error to stderr.

**World and material edits**

Apply valid scene and material changes without rebuilding Swift. Keep the player's position when the world reloads.

**Swift source edits**

Incrementally rebuild only the necessary executable and restart with a serialized scene/session snapshot. Reuse Meadowlight's successful versioned-executable, readiness, rollback and state-restoration ideas.

Do not implement unsafe runtime replacement of Swift types or depend on unloading previously loaded Swift dynamic libraries.

A successful restart restores the player's position and facing direction.

### N0 acceptance gate

A development launch opens the world and keeps it visible. Changing a material or editing the scene or shader updates the live world without a manual restart. A Swift source edit rebuilds and restores the player.

A broken shader or failed Swift build does not destroy the current working session.

**Owner playtest pending:** verify these behaviors before beginning N2. The implementation has not yet been interactively reviewed.

---

## N1: Camera, terrain and the first Floor 1 diorama

**Goal:** Establish a walkable meadow with a complete first pass of the supplied models.

### N1.1: Player camera and controls

Use real 3D geometry and a close perspective camera that follows the player.

Keep the player near the center of the frame. Allow mouse and right-stick orbit, bounded zoom and camera-relative movement.

Use WASD and the left stick for movement. Keep the first walking animation simple.

Ensure objects remain readable at their intended on-screen size. Don't build details that will be invisible at normal zoom.

### N1.2: One authored region

Build a roughly 96 × 96 metre meadow associated with Horunka Forest.

Fill the meadow with grass and small wildflowers over softly uneven terrain. Place each OBJ model from `Assets/Objects` once in a spaced collection around the meadow. Include trees, plants, flowers, mushrooms and rocks so the owner can inspect the supplied assets in the world.

The existing Floor 1 description governs geological materials, vegetation, land use and environmental mood.

Do not generate the entire floor.

The spatial map must carry a stable reference to its Aincrad2 location identity, but no live RPG integration is required.

### N1.3: Simple but attractive rendering

Use simple stylized rendering for the terrain and generated meadow growth. Load model geometry and diffuse textures through Model I/O and MetalKit.

Use:

- Flat or softly shaded mesh facets.
- Carefully selected material colors.
- Instanced grass and wildflowers.
- Alpha cutouts for textured leaves and flowers.
- One dominant directional light.
- Clear ambient fill, contact grounding and soft shadows.

### N1 acceptance gate

A player can walk around a pleasant meadow and inspect every supplied OBJ model with WASD or a game controller. The camera stays close and follows the player. The avatar animates while walking.

**Owner playtest pending:** visual quality, camera feel, and scene composition need hands-on review before beginning N2.

---

## N2: A living, mutable ecological core

**Goal:** Implement a small number of real, interacting environmental systems.

The simulation is CPU-authoritative and independent of rendering, camera movement, or frame rate. Metal is used to visualize the state, not define its ecological truth.

### N2.1: Environmental model

Represent the study region using a small spatial grid plus independently tracked entities.

Suggested grid fields:

- Elevation and terrain material.
- Soil type, water content and drainage.
- Surface water or channel flow.
- Sunlight and canopy shade.
- Ground vegetation biomass.
- Organic matter or a simplified fertility measure.

Keep state mutable and persistable.

Use a coarse simulation grid as necessary; render geometry at a different spatial resolution. A one-metre grid is an initial experiment, not a mandatory universal resolution.

### N2.2: Two feedback systems first

**Water → soil → plants**

Water enters through specified boundary flows, precipitation or surface wetting. Soil retains or drains it according to type and terrain. Plant growth responds to moisture and available light.

Floor 1's river is described as receiving water from springs supplied by the floor above. Preserve that hydrological character in the source conditions rather than assuming all water originates in local rainfall.

**Vegetation → light → growth**

Trees and shrubs compete for available light. Canopy cover shades understory plants. Clearing a small patch creates opportunities for new growth, subject to water and soil conditions.

These should be observable processes, not unrelated random animation parameters.

### N2.3: Time and determinism

Separate graphical frames from ecological simulation time.

Run ecological updates at an appropriate fixed or event-based cadence. Fast-forwarding an in-world week should not require rendering every intermediate frame.

Every simulation run has an explicit seed, initial state, parameter version and ordered intervention log.

Persist enough state to resume without reinitializing the world. Avoid hidden dependence on camera position, wall-clock time or rendering cadence.

### N2.4: Controlled interventions

Provide development tools to:

- Plant or remove a tree.
- Clear an area of undergrowth.
- Change soil moisture or drainage.
- Modify stream inflow.
- Change time of day or season.
- Fast-forward hours, days or weeks.
- Reset or replay a deterministic experiment.

The important requirement is **persistent consequence**: an intervention changes the authoritative world, and its effects survive rendering reloads and save/restore.

### N2 acceptance gate

The user can clear part of a shaded area, advance time and observe an ecologically plausible response in its vegetation.

The user can change water input and observe a corresponding change in soil moisture and nearby plant conditions.

The outcomes are reproducible using the same seed and interventions.

---

## N3: Ecological depth and visual expression

**Goal:** Make the miniature world convincingly alive.

Add complexity one coupled process at a time, only where existing experiments demonstrate a visible deficiency.

Candidate systems, in approximate order:

1. Species-specific moisture and light requirements for oak, hazel, grass and reeds.
2. Plant establishment, maturation, competition, decay and limited seed dispersal.
3. Small-scale erosion, deposition, wetness and terrain response where relevant.
4. Sparse animals with habitat preferences and foraging pressure.
5. Disturbances such as grazing, trampling, coppicing and seasonal variation.

Animals do not initially require battle AI, inventories, social hierarchies, or combat animation.

A boar disturbing vegetation or a small group of grazing animals altering a patch over time is a better initial demonstration than a sophisticated predator system with no ecological consequences.

Define explicit inputs, sinks and conserved quantities where the model requires them. Avoid relying on unexplained random growth or resource creation.

Prioritize visible causal relationships over the number of simulated species.

### N3 acceptance gate

The world shows at least three meaningful, persistent ecological responses to changes in its conditions. The responses are explainable through the simulation model and repeatable in headless experiments.

---

## N4: Art direction and production pipeline

**Goal:** Establish a consistent and economical Floor 1 aesthetic.

Use Aincrad2's existing icons and content documents as references for form, palette, materials, objects, and tone.

The agent should inspect representative icons across vegetation, tools, animals, food and equipment, then prepare a compact visual style sheet for approval.

Do not assume the existing icons automatically translate into an environment style; reconcile their detail level with the chosen camera and world scale.

Use the supplied OBJ, MTL and PNG files through Model I/O and MetalKit. Add direct glTF ingestion later if the asset pack requires it.

Support the mesh and texture features required by the visual direction. Add richer materials when needed.

Curate a small set of excellent reusable assets and procedural variations instead of generating hundreds of unique models.

Polish the scene's natural silhouettes, ground composition, shading, lighting, environmental motion and transitions.

A useful distinguishing feature of Floor 1 is its unusual light beneath the castle's overhead structure. Preserve a sense of that world rather than creating generic fantasy countryside.

### N4 acceptance gate

One small Floor 1 environment is attractive, distinctive and reproducible from authored source assets.

It should remain beautiful with the ecological systems actively changing it.

---

## N5: Prepare for Aincrad2 integration without gameplay

The current Aincrad2 world is organized around named locations, content identities and abstract simulation rules. Nervegear adds continuous spatial realization.

Maintain a narrow translation boundary:

- **Aincrad2 owns:** Canonical names, places, items, species, world lore and eventual RPG semantics.
- **Nervegear owns:** Terrain, spatial placements, rendering, local ecology and persistent local environmental changes.
- **Future integration layer:** Associates Aincrad2 location/entity IDs with Nervegear regions and observed ecological state.

The first version can use a read-only, reproducible export of selected Floor 1 data from `../aincrad2`. There must be no runtime dependency on the Aincrad2 realm server.

Keep the exporter bounded to identifiers and ecological descriptors actually needed by Floor 1.

Preserve provenance and stable IDs; don't invent duplicate canonical definitions in Nervegear.

No effort is required yet to make Aincrad2's abstract encounters or character actions execute in a graphical world.

### N5 acceptance gate

The region can be identified against Aincrad2's Floor 1 source content, and its world state can be exported or inspected through a documented boundary without importing the RPG engine.

---

## Continuous engineering track: scenarios, testing and correctness

**Begin this track with the ecological core in N2. It is not a final testing phase.**

### The core principle

Every useful interactive experiment should be eligible to become a deterministic regression scenario.

**Explore → find useful behavior → save the experiment → add expectations → replay headlessly → retain it as a regression test.**

This should be the dominant testing workflow.

### Scenario representation

A scenario contains:

- A descriptive name and purpose.
- A world seed and content/simulation version.
- Initial ecological state or snapshot.
- An ordered timeline of interventions.
- Simulation time to advance.
- Assertions about observable outcomes.
- Optionally, approved camera views and image references.

Examples:

| Scenario | What it proves |
|---|---|
| `horunka.after-water-inflow` | Increased upstream flow changes nearby wetness without introducing invalid water values. |
| `horunka.clear-coppice` | Removing canopy increases light and alters understory growth over time. |
| `horunka.regrowth` | Newly established vegetation responds predictably to season and available resources. |
| `horunka.drought-recovery` | Water stress reduces growth; recovery follows improved conditions. |
| `horunka.save-resume` | An interrupted and restored simulation reaches the same authoritative final state as an uninterrupted run. |

Scenarios must use the real world state, ecological update engine and production event path. Do not use mocks.

### Headless integration runner

A standalone executable should run the same ecological core as the graphical application.

It loads a scenario, applies interventions, advances the world without drawing, and reports:

- Pass/fail for behavioral expectations.
- Failed invariants with useful context.
- Ordered event trace.
- Selected world measurements.
- Stable state digest and scenario identity.
- Reproduction command.

The runner should execute simulation time as quickly as possible without GPU or rendering requirements.

### Testing philosophy

Favor **system-level behavior and invariants** over large collections of implementation-specific unit tests.

Important properties include:

- Deterministic replay under identical inputs.
- Consistent results across varying rendering frame rates.
- Save/restore equivalence.
- Valid resource and water budgets.
- No negative biomass or invalid physical quantities.
- No unexpected state changes caused by camera movement.
- Correct cleanup and replacement behavior during reload.
- Valid entity references after object removal and world edits.
- Stable operation across long simulated durations.

Where numerical methods are approximate, define tolerances and explain them. Don't demand byte-for-byte equality from quantities the model intentionally approximates.

Keep visual regression captures separate from ecological correctness tests. Golden screenshots detect unintended changes but cannot establish artistic quality.

Avoid broad compiler/test ceremonies after every visual edit. Run fast affected checks during development and the complete regression set at deliberate integration points.

### Acceptance workflow

An agent may propose a scenario, but an accepted behavioral scenario should have an explicit reason for its expectations.

Do not indiscriminately bless the current output as correct.

When behavior is deliberately revised, update the scenario expectation and document why. Historical failures should remain reproducible.

---

## Current project structure

```text
nervegear/
├── Package.swift
├── Makefile
├── Sources/
│   └── Nervegear/          # AppKit, MetalKit, rendering, camera and world
├── Shaders/                # Metal Shading Language
├── Materials/              # Editable material colors
├── Scenes/                 # Floor 1 spatial authoring
└── tools/                  # Build and reload driver
```

Keep the first implementation in one SwiftPM target. Split source files by responsibility only when the code needs it.

Temporary builds, captured video, simulator snapshots and imported caches stay outside version control.

### Available commands

Use the repository's current command surface:

- `make build`: Build the debug executable.
- `make release`: Build the optimized native app.

Never run `make dev*`. Use the fast Swift type check for code verification.

Headless scenarios and image capture are future commands; neither exists yet.

---

## First playtest handoff

The implementation is ready for owner review at the end of N1.

1. Open the updated Nervegear build and review the meadow.
2. Walk with WASD and a game controller.
3. Try camera orbit and zoom.
4. Check the player follow, walking animation, grass and flowers.
5. Report visual or control issues before ecological simulation work begins.

**Stop here for the owner playtest. Do not begin N2 until the review is complete.**

## Definition of first success

Nervegear reaches its first milestone when environment edits appear in a native, GPU-rendered three-dimensional world.

The second success is when changing the environment's *conditions* produces visible, scientifically motivated consequences.

Everything else can wait.
