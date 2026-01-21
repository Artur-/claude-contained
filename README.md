# Claude Code Contained

Run AI coding assistants (Claude, Codex, Gemini, Vibe) inside an [Apple Container](https://github.com/apple/container) sandbox with persistent state. Also works with Docker via `claude-docked`.

There are some caveats:

- **Host localhost access**: `-H PORT` works with `claude-docked` (Docker) but not `claude-contained` (Apple Containers) for services bound to localhost. See [Accessing Host Services](#accessing-host-services).
- **`~/.claude.json` is relocated**: On first run, your `~/.claude.json` is moved to `~/.claude-contained/.claude.json` and replaced with a symlink. This allows containers to share the file. **If you delete `~/.claude-contained/`, you will lose your Claude credentials and settings.**
- **Don't mix contained and uncontained**: Running `claude-contained` and regular `claude` simultaneously may cause issues, as both access the same config file but through different paths. Run one or the other, not both at once.

## Quick Start

### Apple Containers (macOS)

1. Build the container:
   ```bash
   container build --platform linux/arm64 -t claude-contained .
   ```

2. Put `claude-contained` somewhere on your PATH (e.g., `/usr/local/bin`), optionally aliasing to `claude`.

3. Run:
   ```bash
   claude-contained              # Current directory
   claude-contained ./my-project # Specific directory
   ```

### Docker

1. Build the container:
   ```bash
   docker build --platform linux/arm64 -t claude-contained .
   ```

2. Put `claude-docked` somewhere on your PATH.

3. Run:
   ```bash
   claude-docked              # Current directory
   claude-docked ./my-project # Specific directory
   ```

## Usage

```
claude-contained [options] [main_dir] [extra_dir ...] [-- <tool args...>]
```

### Options

| Flag | Description |
|------|-------------|
| `-t`, `--tool TOOL` | AI tool to run: `claude` (default), `codex`, `gemini`, `vibe` |
| `-H PORT[:HOSTPORT]` | Forward host port to container localhost (can be repeated) |
| `-p HOST:CONTAINER` | Publish container port to host (can be repeated) |
| `-s`, `--shell` | Start a bash shell instead of the AI tool (for debugging) |
| `-y`, `--yolo` | Skip all permission prompts (tool-specific flag) |
| `-h`, `--help` | Show help message |

### Supported Tools

| Tool | Command | Yolo Flag | Config Dir |
|------|---------|-----------|------------|
| [Claude Code](https://claude.ai/code) | `claude` | `--dangerously-skip-permissions` | `~/.claude` |
| [OpenAI Codex](https://github.com/openai/codex) | `codex` | `--yolo` | `~/.codex` |
| [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) | `gemini` | `--yolo` | `~/.gemini` |
| [Mistral Vibe](https://github.com/mistralai/mistral-vibe) | `vibe` | `--auto-approve` | `~/.vibe` |

All config directories are bind-mounted regardless of which tool you run.

### Behavior

- First directory is the working directory
- Additional directories are mounted and auto-added via `--add-dir` (Claude and Codex only)
- Tool configs and Maven cache (`~/.m2`) are bind-mounted for persistence
- SSH agent is forwarded automatically

### Examples

```bash
# Tool selection
claude-contained                                    # Claude (default)
claude-contained -t codex .                         # OpenAI Codex
claude-contained -t gemini .                        # Google Gemini CLI
claude-contained -t vibe .                          # Mistral Vibe

# Common usage
claude-contained . ../other/project                 # Multiple directories
claude-contained . -- --model sonnet --verbose      # Pass args to tool
claude-contained -y -t codex .                      # Codex with --yolo
claude-contained -s                                 # Debug shell

# Port forwarding
claude-contained -p 8080:8080 .                     # Expose port 8080
claude-contained -H 3845 .                          # Forward host:3845 to container
```

## Accessing Host Services

The container runs in an isolated network, so `localhost` refers to the container itself, not your Mac. To connect to services running on your Mac, use `host.local` or the `-H` flag.

### Docker (`claude-docked`) - Recommended for Host Services

Use `-H PORT` to forward host ports to container localhost. This works because Docker Desktop has special routing to reach services bound to `127.0.0.1` on the host.

```bash
claude-docked -H 3845 .           # Forward host:3845 to container localhost:3845
claude-docked -H 3845 -H 8080 .   # Multiple ports
```

### Apple Containers (`claude-contained`) - Limited Host Access

Apple Containers can only reach host services bound to `0.0.0.0` (all interfaces), not `127.0.0.1` (localhost only). Most services (including Figma Desktop) bind to localhost only for security. See [apple/container#346](https://github.com/apple/container/issues/346) for the feature request to add `host.docker.internal` equivalent.

**What works:**
- Services you control that bind to `0.0.0.0`
- Using `host.local` hostname for services on all interfaces

**What doesn't work:**
- `-H` flag for localhost-bound services (like Figma Desktop MCP)

For localhost-bound services, use `claude-docked` instead.

### Configuring Figma Desktop MCP

Figma Desktop MCP binds to `localhost:3845`. Use Docker:

```bash
claude-docked -H 3845 .
```

**Requirements:**
- Figma Desktop must be running on your Mac
- The Figma MCP server must be enabled (Figma Desktop → Settings → enable MCP)
- Port 3845 is the default; adjust if you've changed it

### Other MCPs

For MCPs that expect `localhost`, use `claude-docked -H PORT`.

For services bound to all interfaces (`0.0.0.0`), you can use `host.local` in a `.mcp.json` override:

```json
{
  "mcpServers": {
    "my-mcp": {
      "type": "http",
      "url": "http://host.local:PORT/mcp"
    }
  }
}
```

