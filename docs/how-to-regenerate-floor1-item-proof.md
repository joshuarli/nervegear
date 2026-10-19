# Regenerate the Floor 1 item proof

Run these commands from the Nervegear worktree. Set `AINCRAD2_ROOT` to the Aincrad2 checkout.

1. Create a blank Blender file under ignored scratch space.

   ```sh
   mkdir -p .work/tmp
   blender --background --factory-startup --python-expr "import bpy; bpy.ops.wm.save_as_mainfile(filepath='$PWD/.work/tmp/item_factory_start.blend')"
   ```

2. Run the authoring script through Blender MCP's background CLI.

   ```sh
   env TMPDIR="$PWD/.work/tmp" NERVEGEAR_ITEM_REPO="$PWD" AINCRAD2_ROOT="/path/to/aincrad2" \
     uv run --no-project --with mcp python tools/blender_mcp/client.py call execute_blender_code_for_cli \
     "{\"blend_file\":\"$PWD/.work/tmp/item_factory_start.blend\",\"code_file\":\"tools/blender_mcp/build_item_factory_proof.py\"}"
   ```

3. Review `Assets/Items/FactoryProof/review/contact_sheet.png`, the item images in `review/angles/`, and `review/gameplay_distance.png`.

The script writes the Blender source, copied reference icons, OBJ and MTL files, PBR catalog, and review images under ignored `Assets/Items/FactoryProof/`. It reads the Aincrad2 icons but does not change that checkout.
