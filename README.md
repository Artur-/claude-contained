# Claude Code Contained

Run Claude Code inside an Apple Containers sandbox with persistent state.

## Quick Start

1. Build the container:
   ```bash
   container build -t claude-contained .
   ```

2. Put `claude-contained` somewhere on your PATH (e.g., `/usr/local/bin`), optionally aliasing to `claude`.

3. Run:
   ```bash
   claude-contained              # Current directory
   claude-contained ./my-project # Specific directory
   ```

## Usage

```
claude-contained [main_dir] [extra_dir ...] [-- <claude args...>]
```

- First directory is mounted at `/work/main` (working directory)
- Additional directories are mounted as `/work/extraN` and auto-added to Claude via `--add-dir`
- State is persisted in `claude_state` volume (auto-created on first run)
- SSH agent is forwarded automatically

### Examples

```bash
claude-contained                                    # Current directory
claude-contained . ../other/project                 # Multiple directories
claude-contained . -- --model sonnet --verbose      # Pass args to Claude
claude-contained --help                             # Show help
```

## Accessing Host Services

The container runs in an isolated network, so `localhost` refers to the container itself, not your Mac. To connect to services running on your Mac (like Figma Desktop), use `host.local`.

The container automatically configures `host.local` in `/etc/hosts` to resolve to the gateway IP (your Mac).

```bash
# Inside the container, instead of localhost:3000, use:
curl http://host.local:3000
```

### Configuring Figma Desktop MCP

The Figma plugin's `figma-desktop` MCP server defaults to `http://127.0.0.1:3845/mcp`, which won't work inside the container. To fix this, create a `.mcp.json` file in your project directory:

```json
{
  "mcpServers": {
    "figma-desktop": {
      "type": "http",
      "url": "http://host.local:3845/mcp"
    }
  }
}
```

This overrides the default URL so the container can reach Figma Desktop running on your Mac.

**Requirements:**
- Figma Desktop must be running on your Mac
- The Figma MCP server must be enabled (Figma Desktop → Settings → enable MCP)
- Port 3845 is the default; adjust if you've changed it

### Other MCPs

For any MCP that needs to connect to a service on your Mac, replace `localhost` or `127.0.0.1` with `host.local` in the MCP configuration.

