import argparse
import asyncio
import json
import os
import shutil
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


SERVER_SOURCE = "git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp"


def parse_arguments():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list")
    call = commands.add_parser("call")
    call.add_argument("tool")
    call.add_argument("arguments", nargs="?", default="{}")
    return parser.parse_args()


async def main():
    arguments = parse_arguments()
    executable = os.environ.get("BLENDER_MCP_UVX") or shutil.which("uvx") or "uvx"
    source = os.environ.get("BLENDER_MCP_SOURCE", SERVER_SOURCE)
    environment = os.environ.copy()
    environment["BLENDER_MCP_HOST"] = os.environ.get("BLENDER_MCP_HOST", "127.0.0.1")
    environment["BLENDER_MCP_PORT"] = os.environ.get("BLENDER_MCP_PORT", "9876")
    parameters = StdioServerParameters(
        command=executable,
        args=["--from", source, "blender-mcp"],
        env=environment,
    )
    async with stdio_client(parameters, errlog=sys.stderr) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            if arguments.command == "list":
                result = await session.list_tools()
                for tool in result.tools:
                    print(f"{tool.name}\t{tool.description}")
                return 0

            try:
                payload = json.loads(arguments.arguments)
            except json.JSONDecodeError as error:
                raise SystemExit(f"arguments must be a JSON object: {error}") from error
            if not isinstance(payload, dict):
                raise SystemExit("arguments must be a JSON object")
            code_file = payload.pop("code_file", None)
            if code_file is not None:
                payload["code"] = Path(code_file).expanduser().read_text(encoding="utf-8")
            result = await session.call_tool(arguments.tool, payload)
            for block in result.content:
                if block.type == "text":
                    print(block.text)
                elif block.type == "image":
                    print(f"[image result: {block.mimeType}, {len(block.data)} encoded bytes]")
                else:
                    print(json.dumps(block.model_dump(), ensure_ascii=False))
            return 1 if result.isError else 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
