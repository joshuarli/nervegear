# Nervegear project roadmap

**Status:** N0.1–N0.3 and N1 implemented; original N1 player playtest pending. **N1.5 is the newly authorized P0 visual-quality campaign, effective immediately; N2–N5 expansion is on hold until its owner-reviewed gate.**
**Platform:** macOS native desktop
**Source of world canon:** `../aincrad2`
**First playable region:** Floor 1
**Primary priorities:** Iteration speed (preserve) → **N1.5 reference-matched hero scene (P0)** → ecological simulation → world expansion

## Vision

Nervegear is a native graphical world for Aincrad2. You play in a small, walkable section of Floor 1, viewed through a close third-person camera.

Its first objective is not to recreate Aincrad2's RPG systems. It is to make a small section of Floor 1 feel alive.

The player should be able to watch weather change, observe vegetation responding to soil and light, see animals alter their surroundings, and modify the environment while the consequences unfold over time.

The first visual milestone is a **convincing, walkable, naturalistic rocky meadow** with the visual character of the owner's supplied reference screenshot. It must be achievable with the present native Metal renderer and existing hot-reload workflow, not a new game engine.

### Non-goals

- No gameplay mechanics port from Aincrad2 yet.
- No combat, quests, inventories, skill systems, or NPC dialogue.
- No multiplayer or server integration.
- No mobile, browser, or cross-platform implementation.
- No enormous procedurally generated world.
- No proprietary game engine.
- No vast photorealistic world or engine-scale realism rewrite. **Naturalistic, textured, reference-grade fidelity within one tiny hero scene is explicitly in scope.**
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

Build a 30 × 30 metre meadow associated with Horunka Forest.

Fill the meadow with grass and broadleaf plants over softly uneven terrain. Place every environment OBJ exported from the supplied `verdant_trail.blend` at least once in a readable collection. The source includes trees, plants, grass, rocks, stones, roots and deadwood. It has no flower or mushroom meshes.

The existing Floor 1 description governs geological materials, vegetation, land use and environmental mood.

Do not generate the entire floor.

The spatial map must carry a stable reference to its Aincrad2 location identity, but no live RPG integration is required.

### N1.3: Simple but attractive rendering

N1 established inexpensive initial rendering for the terrain and generated meadow growth. **N1.5 supersedes N1's placeholder-art quality bar**, while retaining Model I/O, MetalKit and the lean native rendering architecture.

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

## N1.5: P0 rocky meadow visual north star — reference-match recovery (**DO NEXT**)

**Priority and authorization:** This narrowly scoped campaign takes precedence over N2 ecology, N3 ecological depth, general N4 art production, N5 integration, and any further wide-area scene population. The owner specifically authorized work to adapt the current Poly Haven **A Verdant Trail** scene toward the photograph they provided (sunlit grasses, broadleaf thickets, rounded pale weathered boulders, open woodland and distant rolling hills). Continue safeguarding N0 hot reload and N1 movement; neither is to be rewritten. The original N1 hands-on review is still pending, and **only the owner can accept the N1.5 aesthetic**. Do not mistake an agent's screenshot appraisal for approval.

### Objective and visual contract

Produce one **art-directed, convincing 30 × 30 m Floor 1 rocky-meadow hero region**, first in an editable Blender scene, then **visibly comparable inside native Nervegear Metal while walking around**. The hero scene is a technical and artistic quality reference for later ecology, not a gameplay level, new engine, large biome generator or high-poly simulation.

**Target appearance (source of truth: owner's supplied photo, not a generic "Genshin", "Ghibli" or fantasy-packs mood board):**

- Ground: irregular lush, fine-bladed grass in clumps and separated patches; dark green shaded bases, straw-golden illuminated tips, varying heights/widths; a little exposed warm reddish earth, occasional very small flowers and debris. No solid plastic-green lawn or wall-to-wall identical upright cards.
- Rocks: irregular, naturally rounded, **pale neutral-grey to warm-beige** stone, pitting/mineral discoloration, subtle weathering, relatively sparse moss; half-sunken boulders in **related geological clusters**, not isolated evenly distributed OBJ specimens. Some rocks larger than the player's torso, some fist-sized.
- Plants: layered low grass → taller grass and forbs → irregular rounded broadleaf shrubs → a few airy deciduous crowns and distant wooded edges. Dense central thickets with **clear openings** and asymmetrical silhouettes. Do not enlarge small shrubs 3× merely to impersonate mature trees.
- Terrain/composition: gentle but purposeful relief, hummocks, hollows, rock outcrops, traversable grassy slots, one inviting implied footpath, foreground/midground/distant separation. Not a sinusoid with randomly scattered objects; no cliffs or dramatic fantasy ruins.
- Light/grade: calm slightly warm afternoon sun, soft credible shadows/contact, neutral bright sky, subtle airy distance, natural restrained saturation and non-plastic roughness. Avoid dark fantasy, candy colors, flat-shaded geometric foliage, excessive bloom and artificial color casts.
- World canon: Floor 1 Horunka is temperate oak/hazel countryside per `../aincrad2/docs/floors/01-town-of-beginnings.md`. The supplied photograph is the **visual/fidelity/composition benchmark**, not a request to transplant a botanically inconsistent South African biome verbatim. Use it to establish beauty; substitute oak/hazel-like or other appropriate broadleaf silhouettes with licensing-verified models where necessary. Preserve the `aincrad2Location` identity.

**Reference availability:** The exact owner-supplied photograph must be accessible to the implementing agent as an external reference, e.g. locally at `References/rocky-meadow-target.png` (suggested location; **not currently asserted to exist**) or in the agent's attached images. Record its real local path/identity and include it in contact-sheet comparisons. Do not silently replace it with a vaguely similar image found online, AI render or a retouched output; if unavailable, complete an asset audit and baseline capture, then request it **before claiming visual acceptance**. Do not redistribute the owner's unknown-license reference as a runtime game asset.

### What currently exists — use it, do not restart

Inspect the latest implementations, not older assumptions:

- `Scenes/world.json`: fixed-seed 30 m scene already places **multiple boulders, rock faces and repeated shrubs** and scatters four `Wild_Grass` variants plus three shrub variants (~4,950 requested scatter instances); do not claim the project is still one grass model and three rocks. The crowd is nearing the scene validator's 5,000-instance cap; **raising counts alone is not an artistic solution**.
- `tools/blender_mcp/export_verdant_assets.py`: already adapts/export-selects fourteen named OBJ assets, multiple grass variants, textures and material catalog; includes rock-resting logic and aggressively green-tinted material factors. Audit/replace questionable scaling or tinting only with before/after evidence. It exports from an existing `verdant_trail.blend` plus sibling textures into `Assets/Objects`, which is intentionally gitignored.
- `docs/blender-mcp.md`: existing Blender Lab/MCP bridge and reproducible export procedure. Use this route or a safe batch Blender script, not a new toolchain.
- `Sources/Nervegear/ModelAssetLoader.swift`, `SurfaceMaterials.swift`, `Shaders/World.metal`: native Model I/O mesh import, diffuse/PBR textures, opacity-masked double-sided vegetation, instanced draws and directional shadowing already exist. Validate parity before building new shader abstractions.
- `Sources/Nervegear/WorldData.swift`: current scatter is seed-stable but spatially uniform with only path/rock exclusions; `TerrainHeight` supplies simple terrain. This placement model is the most likely **artistic** limitation, alongside insufficient source plant/tree variety and scene composition.
- `Sources/Nervegear/MetalWorldRenderer.swift`: current renderer has screenshot capture (`--capture-on-launch` writes `.work/tmp/scene.png`), scene/material/shader reload and a working camera/avatar. Preserve these, the current safe rollback behavior, and existing input.
- `Makefile`, `tools/dev.swift` and `plan.md`: **respect current development command restrictions** (including the current prohibition on `make dev*` in the Available commands section). Check the actual available command(s) before invoking; do not promise or invent a new CLI.

**No dependency on a new glTF loader, Unreal/Unity, RealityKit, a terrain editing GUI, generalized ECS, full physics, runtime Blender, or additional paid asset generators.** All source scans must have a documented commercial-use license; Poly Haven's CC0 assets are a safe first pool. Keep source geometry and materials, not screenshots baked as textures.

### N1.5.0 — Audit, frozen baseline and photographic breakdown

1. Inspect `plan.md`, live scene, latest export code, relevant PBR/terrain shader code, and source Blender scene. Inventory *all* useful original Verdant Trail meshes (and unused variants), geometry scale/axis, diffuse/normal/roughness/opacity maps, and present on-screen proportions. Separate "not imported" from "imported but not placed" and "placed but visually bad".
2. Render the real **current Metal** baseline and record a short native walkthrough. Save fixed world seed, camera transform/FOV, player position, light, resolution, mesh counts, draw calls, frame time and source asset provenance. Use a repeatable capture; keep bulk PNG/video in ignored `.work/`. Do not forge a Blender image as an engine screenshot.
3. Make an explicit **reference-to-scene gap ledger** with at least these components: grass morphology/coverage, shrub crowns, mature trees, boulder geometry/material, rock grounding, terrain relief, vegetation clustering, color/exposure, shadows/atmosphere and distance. For each, mark whether the best remedy is an existing mesh, a different licensed asset, Blender art edit, composition-mask edit, or small Metal shading fix.
4. Select a small visual vocabulary. Prioritize the owner's image over sheer pack/model count. First use the already licensed Verdant Trail sources; source 1–3 additional *verified free* assets only for truly missing silhouettes (e.g. deciduous canopy or meadow grass). If nothing free is good enough, **report the gap** rather than import cartoon-looking substitutes.

**Deliverable:** visual gap ledger, material/mesh inventory, baseline PNGs and chosen hero camera. Do not pass based on CI or asset count.

### N1.5.1 — Create the hero scene in Blender before scaling runtime generation

1. Duplicate the source `.blend` into a **separate, nondestructive Nervegear art scene**; preserve licensed originals and provenance. Blender MCP can place and modify objects, materials, Geometry Nodes and lighting, but the saved art file must remain editable by hand; keep semantic names for reusable assets and authoring groups.
2. Compose **one camera-matched scene** at approximately the screenshot's relative eye height and distance. Start with a few carefully oriented, interlocking weathered rocks, an irregular shrub mass, several grass strata, a darker wooded edge and an opening/path through the vegetation. Hand-author *formations*, not a scattering of unrelated instances. Establish a good hero frame before populating the remaining 30 m.
3. Use source PBR scans wherever possible. Reorient, partially bury, vary scale **within plausible bounds**, repair normals/UVs, and selectively recolor materials. **Do not** solve silhouette mismatch with strong green tints or extreme 3–4× enlargement of a small shrub. Replace the mesh/plant when shape is wrong.
4. Author deterministic spatial **density/height/species/soil/rock-exclusion masks** or simple editable formation definitions for grass, shrubs and trees. Keep paths and composition openings legible. This will later serve N2 light/moisture ecology; don't implement growth or weather simulation now.
5. Light with a broad neutral-warm sun, plausible sky/ambient fill and modest haze; audit color management/tone mapping. Use real UV textures/normal maps. Save **a Blender reference render at a known resolution/camera**, plus overhead formation/mask view and asset inventory.
6. Review the Blender scene through at least five viewpoints: hero, player-height approach, side, reverse and overhead. **It is a three-dimensional game**, not a projection trick that falls apart behind the original camera. Fix obvious repetition and billboarding/occlusion artifacts before export.

**Owner gate A:** Show the Blender hero render and five-view contact sheet compared with the supplied photo; explicitly list where it still differs. **Stop for an owner aesthetic verdict before expensive generalization.** If the human is unavailable, complete reproducible export preparation but do not self-certify the art.

### N1.5.2 — Reusable Blender → Nervegear export and semantic scene parity

1. Extend the **existing** `tools/blender_mcp/export_verdant_assets.py` rather than rewriting the whole importer. Export only validated assets, complete intended textures and deterministic asset/transform/formation data. Keep a clear authoring convention (meters, axes, origin, upright, ground contact, winding, alpha). Record source file and license per asset. Avoid committing large raw CC0 packs unless deliberately approved; keep `Assets/` gitignored.
2. The exported scene must not collapse into a single giant static mesh. Keep **distinct mesh identities and stable per-instance IDs**, terrain/formation masks, group placements and collision/footprint proxies separate from decorative geometry. Distinguish editable terrain geometry from foliage, boulders and canonical future ecological entities.
3. Update `SceneDocument`/`WorldData.makeObjects` narrowly so the same source mesh can be deliberately placed in many positions, and **do not let global scatter RNG scramble authored placements**. Validate stable IDs, deterministic order, duplicate source usage, bounds and explicit failures for missing art. Preserve the default scene or add a clearly named alternate hero study so the owner can switch safely.
4. Replace unrestricted uniform random shrub/grass scattering with **art-directed, seed-stable density masks and clustered distributions** only as needed for this one study. Distinguish bare soil, sparse exposed meadow, dense grass pockets, protected shrub thickets, rock margins and trail clearance. Preserve spatial seeds across asset re-export and shader reload. Do not build a generic biome compiler or procedural ecology.
5. Preserve Nervegear's existing Model I/O/Metal geometry, alpha masks, mipmaps and PBR textures. Export/repack textures in suitable formats with correct sRGB vs linear channel treatment; verify normal handedness and double-sided leaf normals. Ensure material variation persists without nonphysical channel tinting. Add tangents, alpha-aware mip handling, shadow cutouts or improved texture/lighting only if a *specific visible mismatch* requires it.
6. Ensure actual ground height matches visible terrain and the player walks naturally across slope/rock margins. If authored height/paint masks replace procedural sine terrain, make **rendering, player placement and future ecology share one canonical height/mask source**; no two competing terrain definitions. Avoid rock levitation, sunk shrubs and clipping into a hidden procedural ground plane.
7. Preserve the current hot-reload loop: tune materials, arrangement, masks, lighting and vegetation density without a full Swift rebuild. On failed data/asset validation retain the last good scene; only explicitly changed assets should require offline Blender re-export. Don't add heavyweight live Blender dependency to gameplay.

**Deliverable:** saved editable Blender source, trusted repeatable export recipe, asset/source manifest, small scene/mask data changes, and a successful native reload of the transformed hero scene.

### N1.5.3 — Reproduce the Blender result in Metal, not approximately

1. Capture **identical** camera poses/FOV, world scale, time of day/sun direction, resolution and content selection in Blender and Nervegear. Compare tone maps/working color space, albedo, rock roughness/normal detail, foliage alpha silhouettes, ambient/direct light, shadows, haze and surface grounding.
2. For each visual defect, demonstrate the smallest responsible fix: wrong source scale/orientation, missing alpha, wrong texture color space, improper vegetation normals, incorrect material factors, inaccurate terrain blending, absent sky/ambient light, LOD/draw-order or camera mismatch. Do not answer each discrepancy by adding another general-purpose rendering subsystem.
3. Existing `Shaders/World.metal` supports GGX-like PBR, terrain blending and directional shadows, but the current ambient/tonemapping is simple and path/rock weighting is authored largely in shader terms. Add **localized** improvements where they materially raise fidelity: painterly-naturalistic ambient/sky lighting, rock-to-ground contact, diffuse grass illumination, physically plausible warm sunlight, gentle atmospheric aerial perspective and controllable terrain splat masks. Avoid GI/ray tracing, proprietary runtime engines, giant post-processing stacks or custom HDR render graphs without proof of necessity.
4. Fix alpha-cutout edges/shadow artifacts and harsh grass repetition at walking distance. Test from normal third-person camera height and zoom, not only the hero screenshot. Do not sacrifice coherent scale, playable paths or player visibility for a prettier overhead still.
5. Keep iterations rapid: a material, light or layout edit should reflect through existing watch/reload; document when Blender export is actually required. Build one repeatable Blender-vs-Metal contact sheet with synchronized views and a concise **mismatch → cause → fix → remaining** ledger. Pixel diffs may flag drift but cannot certify artistic quality.

**Owner gate B:** The owner inspects the **real Metal** hero frame and short native walk against the Blender study and original photo. Human acceptance is required; model-generated confidence or a passing screenshot hash is not enough.

### N1.5.4 — Walking polish, practical performance and reproducibility

- Retain existing close third-person controls and avatar. Demonstrate a roughly 60–90-second continuous walk through the authored formations, with foreground grass, varied shrub depth, near/far rocks, openings, and turning the camera both directions. No sudden wall of foliage, ugly reverse silhouettes, floating/sunken assets or abrupt scene-boundary emptiness in the normal route.
- Profile **actual hardware** on this small scene: 1440p steady ~60 FPS is an initial aspiration, not a reason to reduce asset quality blindly. Report median/p95 frametime, CPU/GPU time where measurable, draw calls, vegetation instance counts, triangles, texture memory and reload latency. Fix **measured** hotspots (foliage overdraw, instance submission, texture size/mips, shadow work). Preserve a lower-cost debug art preset when necessary.
- No arbitrary vegetation count escalation. The present 5,000-instance validator ceiling is a project constraint, **not a beauty target**; design texture cards/cluster meshes, LOD and instance batches judiciously. Increase limits only after profiling and validation.
- Add a small repeatable **visual smoke fixture** for fixed seed, selected material/asset IDs, named camera positions, and image capture. It may detect broken import, wrong alpha or nondeterministic placement, but it does **not** replace real art feedback. Preserve screenshots as review artifacts and one accepted scene configuration as a regression case.
- Protect the content supply chain: CC0/license/provenance manifest with source links, texture names and transformations; clear re-export steps and documented missing-local-asset behavior. Do not commit raw asset bundles without intent, commercial-license verification, or enormous binaries.
- Maintain the existing N0 hot-reload and player-state persistence. Check a failing shader edit, missing asset, invalid authored mask and successful asset update all leave the previous valid scene running until a safe replacement is ready.

### Required handoff, exit criteria and stop condition

Every numbered tranche produces **one reviewable artistic result** (not a mass of unattended tickets). At handoff provide:

1. Commit(s), exact input asset versions/rights, working Blender file path and deterministic export instructions.
2. Source photo vs Blender hero vs **actual Metal** hero at comparable composition, plus five-angle and walking evidence. Clearly label origins; never substitute a rendered concept mockup for running Nervegear.
3. Scene seed, named camera transforms, light/exposure settings, reproducible asset manifest and saved scene/mask definitions.
4. Specific reference-gap ledger with visible improvements and known compromises; owner’s recorded artistic feedback or explicit `PENDING OWNER REVIEW`.
5. Tests of asset validation, scene restore, deterministic placement, shader/scene reload safety, player collision, and an honest profile of native performance.
6. The **next smallest artistic decision**, not a speculative ecology backlog.

**N1.5 is done only when the owner explicitly approves both** (a) a Blender hero scene that genuinely resembles the screenshot in shape, material richness, light and composition, **and** (b) comparable native Metal output that remains attractive from normal playable viewpoints. This is deliberately a higher bar than "all meshes imported", "60 FPS", "all tests passed" or "looked fine to the agent". **Until this gate: N2, N3, large-scale N4, N5, extra floors, new wildlife and complex ecology remain paused.**

### Immediate agent instruction (begin now)

Read the latest `plan.md`, `docs/blender-mcp.md`, `Scenes/world.json`, `Sources/Nervegear/WorldData.swift`, `Sources/Nervegear/ModelAssetLoader.swift`, `Sources/Nervegear/MetalWorldRenderer.swift`, `Shaders/World.metal`, `tools/blender_mcp/export_verdant_assets.py`, and `../aincrad2/docs/floors/01-town-of-beginnings.md`. First deliver the **N1.5.0** baseline/gap ledger and the **N1.5.1 Blender hero scene**; get the owner's reaction. Then adapt/export only what is necessary, bring up the matching scene in Metal, compare and iterate. **Do not resume N2 just because the current N1 implementation builds.** 

---

## N2: A living, mutable ecological core

**ON HOLD:** Do not begin N2, N3, broad N4 content production, or N5 until the N1.5 environment has passed its explicit owner review. N1.5 may prepare ecological spatial identities and masks, but must not implement new ecological dynamics.

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

**Goal (deferred):** Extend the **approved N1.5** environment language into a sustainable Floor 1 asset-production workflow *after* ecological experiments justify expansion. N1.5 already owns the immediate visual direction, initial asset adaptation and Blender-to-Metal fidelity proof; do not restart those from scratch here.

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
