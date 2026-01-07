# Claude Code Contained

Run Claude Code inside an [Apple Container](https://github.com/apple/container) sandbox with persistent state.

There are some caveats:

- Currently does not forward ports for local MCPs such as Figma Desktop

## Quick Start

1. Build the container:
   ```bash
   container build --platform linux/arm64 -t claude-contained .
   ```

3. Put `claude-contained` somewhere on your PATH (e.g., `/usr/local/bin`), optionally aliasing to `claude`.

4. Run:
   ```bash
   claude-contained              # Current directory
   claude-contained ./my-project # Specific directory
   ```

## Usage

```
claude-contained [options] [main_dir] [extra_dir ...] [-- <claude args...>]
```

### Options

| Flag | Description |
|------|-------------|
| `-s`, `--shell` | Start a bash shell instead of Claude Code (for debugging) |
| `-h`, `--help` | Show help message |

### Behavior

- First directory is mounted at `/work/<project-name>` (working directory)
- Additional directories are mounted as `/work/extraN` and auto-added to Claude via `--add-dir`
- State is persisted in `claude_state` volume (auto-created on first run)
- SSH agent is forwarded automatically

### Examples

```bash
claude-contained                                    # Current directory
claude-contained . ../other/project                 # Multiple directories
claude-contained . -- --model sonnet --verbose      # Pass args to Claude
claude-contained --help                             # Show help
claude-contained -s                                 # Debug shell in current directory
claude-contained -s ./my-project                    # Debug shell with specific directory
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

