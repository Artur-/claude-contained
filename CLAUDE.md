# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code Contained is a bash-based containerization wrapper that runs AI coding assistants (Claude, Codex, Gemini, Vibe) inside an Apple Containers sandbox with persistent state. It enables isolated, repeatable sessions on macOS with support for multi-project workflows and host service access.

## Build and Run Commands

```bash
# Build the container image
container build -t claude-contained .

# Run Claude (default)
claude-contained

# Run other tools
claude-contained -t codex .
claude-contained -t gemini .
claude-contained -t vibe .

# Run with multiple directories (first is working dir, others auto-added for claude/codex)
claude-contained . ../other/project

# Pass arguments to tool (use -- separator)
claude-contained . -- --model sonnet

# Yolo mode (maps to tool-specific flag)
claude-contained -y -t codex .
```

## Architecture

### Key Files

- **claude-contained** - Main bash entry point for Apple Containers. Handles argument parsing, path resolution (with Python3/realpath/readlink fallbacks), and container execution with full path parity.

- **claude-docked** - Docker equivalent of claude-contained. **Must be kept in sync with claude-contained** to maintain feature parity. Both scripts share the same flag interface and behavior.

- **Dockerfile** - Builds on Node 20 (Debian Bookworm). Installs JetBrains Runtime 21, HotswapAgent, AI CLI tools (Claude Code, OpenAI Codex, Google Gemini CLI, Mistral Vibe), ripgrep, Python 3. Creates entrypoint.sh that configures `host.local` for host service access, matches host UID/GID, and sets up path parity.

- **.mcp.json** - MCP server configuration, notably enabling Figma Desktop MCP via `host.local:3845`.

### Container Design

- **Full path parity**: Directories mounted at their original host paths (e.g., `/Users/me/project` → `/Users/me/project`)
- **HOME parity**: Container HOME matches host HOME for consistent behavior
- **UID/GID matching**: Container user matches host user IDs for proper file permissions
- **State sharing**: Tool configs (`~/.claude`, `~/.codex`, `~/.gemini`, `~/.vibe`) bind-mounted from host
- **SSH agent forwarding**: Disabled by default for security; enable with `-S/--ssh` flag (required for `git push` to SSH remotes)
- Host services accessible via `host.local` hostname (resolved from container gateway IP)

### Notable Patterns

- Path resolution prioritizes Python3 for reliability, with multiple fallbacks
- Entrypoint dynamically adjusts UID/GID to match host user (handles conflicts)
- Strict bash error handling with `set -euo pipefail`
- `--` separator distinguishes directory arguments from tool arguments
- `-t/--tool` flag selects which AI tool to run; `-y/--yolo` maps to tool-specific permission flags
- Only Claude and Codex support `--add-dir` for extra directories; others just get mounts
- **Script parity**: `claude-contained` and `claude-docked` should always be updated together when adding/changing flags or behavior to maintain feature parity across both container runtimes

### Devcontainer Support

The `devcontainer-template/` directory provides a VS Code devcontainer configuration for Java/Spring development.

**Key design decisions:**

- **Template directory, not in-repo `.devcontainer/`**: Users copy to their own projects; avoids confusion with developing claude-contained itself
- **`workspaceMount: ""`**: Disables VS Code's default `/workspaces` mount to enable path parity
- **`overrideCommand: true`**: Bypasses entrypoint.sh since VS Code manages container lifecycle; setup done via `postCreateCommand`
- **Pre-built image reference**: Simpler than embedding Dockerfile; users build once, reuse everywhere

**Differences from standalone scripts:**

- VS Code manages the container lifecycle, not entrypoint.sh
- UID/GID handled by VS Code's `remoteUser` feature (may differ from host)
- Networking managed by VS Code; `host.local` trick may not work

## Known Caveats

- Port forwarding not available for local MCPs (use `host.local` workaround)
- Multiple simultaneous sessions share `~/.claude` state; concurrent writes may conflict (Claude Code limitation)
- `~/.claude.json` is relocated to `~/.claude-contained/.claude.json` (with symlink at original location) to work around Apple Containers' inability to bind-mount individual files. Deleting `~/.claude-contained/` will lose credentials.
- Running `claude-contained` and regular `claude` simultaneously is not recommended (both access same config via different paths)
- **Devcontainer limitation**: Don't run VS Code devcontainer and standalone scripts simultaneously on same `~/.claude` directory
