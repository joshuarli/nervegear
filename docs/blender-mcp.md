# Connect Blender to Codex with Blender MCP

Use the Blender Lab add-on and the local MCP bridge to inspect a scene or run a trusted Blender Python script.

## Start the Blender server

1. Install and enable the [Blender MCP Server add-on](https://www.blender.org/lab/mcp-server/).
2. Open the `.blend` file you want to work with.
3. Set the add-on host to `127.0.0.1` and its port to `9876`.
4. Start the add-on server.

Keep the server on loopback. The code tool runs Python inside Blender, so connect only trusted clients and stop the server when you finish.

## Connect Codex

Install `uv` if `uvx` is not on your `PATH`. Register the Blender MCP bridge:

```sh
codex mcp add blender \
  --env BLENDER_MCP_HOST=127.0.0.1 \
  --env BLENDER_MCP_PORT=9876 \
  -- uvx --from 'git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp' blender-mcp
```

Run `codex mcp list` to confirm the `blender` server is enabled. Codex uses the same MCP configuration in its CLI and IDE extension. Restart Codex if the Blender tools do not appear.

## Call Blender tools from this repository

The repository client starts the upstream bridge and connects to the Blender add-on:

```sh
uv run --no-project --with mcp python tools/blender_mcp/client.py list
```

Use `call` with a tool name and a JSON object to invoke a tool. Pass `code_file` to run a local Python file with `execute_blender_code`:

```sh
uv run --no-project --with mcp python tools/blender_mcp/client.py call execute_blender_code '{"code_file":"tools/blender_mcp/export_verdant_assets.py"}'
```

Run commands from the repository root. The client prints text and image result summaries, then exits with a nonzero status when the MCP tool reports an error.

## Export the meadow assets

`tools/blender_mcp/export_verdant_assets.py` exports the boulder, rock, shrub, and wild grass meshes used by the meadow scene. It writes OBJ and MTL files, converted texture maps, and a `materials.json` catalog. The script expects a saved source `.blend` file, the named source objects, and a sibling `textures` directory.

By default, the script writes to `NervegearExport` beside the source `.blend` file. To use different directories, set `NERVEGEAR_SOURCE_TEXTURES` or `NERVEGEAR_ASSET_OUTPUT` in Blender's Python Console before calling the script:

```python
import os
os.environ["NERVEGEAR_SOURCE_TEXTURES"] = "/absolute/path/to/textures"
os.environ["NERVEGEAR_ASSET_OUTPUT"] = "/absolute/path/to/Assets/Objects"
```

The script duplicates source meshes for export and does not save changes to the `.blend` file.

The script targets the current meadow asset names and texture filenames. Update its `asset_objects` and `texture_specs` tables when the source asset pack changes.

## References

- [Blender MCP Server add-on](https://www.blender.org/lab/mcp-server/)
- [Codex MCP setup](https://learn.chatgpt.com/docs/extend/mcp)
