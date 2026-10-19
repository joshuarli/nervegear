# Floor 1 item factory proof

This proof models 12 Floor 1 items from the Aincrad2 catalog. The authoring script uses Blender Python helpers for turned vessels, shaped metal, cut wood, organic forms, and baked food. Each item remains an editable Blender mesh with named material slots.

The source descriptions come from `content/floors/1/codex.kdl`. The item definitions come from `content/floors/1/items.kdl`. The matching icons come from `content/icons/`.

| Item | Construction family | Description constraint |
| --- | --- | --- |
| Tolbana Iron Sword | Forged sword | Straight double-edged blade, plain cross, disc pommel |
| Field Lantern | Sheet-metal assembly | Tin body, horn window, wire bail, stable base |
| Lamp Oil | Filled flask | Yellow seed oil sold by the flask |
| Sawn Timber | Cut lumber | Oak and ash boards from Horunka's sawpit |
| Kobold Iron | Raw metal | Dark, soft bog-ore iron lump |
| Hollow Amber | Polished resin | Thumb-sized clear yellow bead |
| Nepent Ovule | Plant seed-bulb | Pale bulb taken whole from beneath the bloom |
| Brown Cap Mushroom | Fungus | Firm brown cap from oak leaf litter |
| Mutton Pie | Baked food | Wedge with a thick butter crust and a gravy hole |
| Wolf Fang | Bone tooth | Canine used for rivets, edge settings, and toggles |
| Boar Hide | Cured hide | Thick at the shoulder and thin at the belly |
| Wild Honey | Honeycomb | Dark comb cut from a hollow oak |

The Blender source stores the 12 meshes and packed reference icons in `Assets/Items/FactoryProof/floor1_item_factory.blend`. Blender renders a reference-icon contact sheet, five views per item (front, side, back, three-quarter, and top), and a true-size tabletop preview from a 4.5 m perspective camera. The tabletop preview includes a 1.70 m scale marker.

The exporter writes one Y-up OBJ and MTL per item plus `materials.json`. The catalog carries base-color, roughness, and metal factors. It has no texture maps. Blender uses small procedural color variation on wood and hide, but the OBJ export does not bake that variation. The props-only catalog has no terrain layers. Nervegear's current environment loader requires three terrain layers, so runtime registration needs a props-only catalog path. This proof does not change the runtime importer or register the objects in Nervegear.

The flask design, sale-unit sizes, board count, mushroom anatomy, pie serving size, hide folds, honeycomb outline, and all unlisted proportions are estimates. The script records these estimates beside each item definition. It leaves the ovule plain because the codex does not describe the plant's anatomy.

Generated geometry, materials, previews, and copied icons remain under ignored `Assets/Items/FactoryProof/`. The tracked files contain only the procedural authoring script, this report, and the regeneration instructions.
