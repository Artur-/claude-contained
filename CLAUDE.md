# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code Contained is a bash-based containerization wrapper that runs Claude Code inside an Apple Containers sandbox with persistent state. It enables isolated, repeatable Claude Code sessions on macOS with support for multi-project workflows and host service access.

## Build and Run Commands

```bash
# Build the container image
container build -t claude-contained .

# Run with current directory
claude-contained

# Run with specific directory
claude-contained ./my-project

# Run with multiple directories (first is working dir, others auto-added)
claude-contained . ../other/project

# Pass arguments to Claude Code (use -- separator)
claude-contained . -- --model sonnet
```

## Architecture

### Key Files

- **claude-contained** - Main bash entry point for Apple Containers. Handles argument parsing, path resolution (with Python3/realpath/readlink fallbacks), and container execution with full path parity.

- **claude-docked** - Docker equivalent of claude-contained. **Must be kept in sync with claude-contained** to maintain feature parity. Both scripts share the same flag interface and behavior.

- **Dockerfile** - Builds on Node 20 (Debian Bookworm). Installs JetBrains Runtime 21, HotswapAgent, Claude Code npm package, ripgrep, Python 3. Creates entrypoint.sh that configures `host.local` for host service access, matches host UID/GID, and sets up path parity.

- **.mcp.json** - MCP server configuration, notably enabling Figma Desktop MCP via `host.local:3845`.

### Container Design

- **Full path parity**: Directories mounted at their original host paths (e.g., `/Users/me/project` → `/Users/me/project`)
- **HOME parity**: Container HOME matches host HOME for consistent behavior
- **UID/GID matching**: Container user matches host user IDs for proper file permissions
- **State sharing**: `~/.claude` bind-mounted from host (enables multiple simultaneous sessions)
- SSH agent forwarding enabled
- Host services accessible via `host.local` hostname (resolved from container gateway IP)

### Notable Patterns

- Path resolution prioritizes Python3 for reliability, with multiple fallbacks
- Entrypoint dynamically adjusts UID/GID to match host user (handles conflicts)
- Strict bash error handling with `set -euo pipefail`
- `--` separator distinguishes directory arguments from Claude Code arguments
- **Script parity**: `claude-contained` and `claude-docked` should always be updated together when adding/changing flags or behavior to maintain feature parity across both container runtimes

## Known Caveats

- Port forwarding not available for local MCPs (use `host.local` workaround)
- Multiple simultaneous sessions share `~/.claude` state; concurrent writes may conflict (Claude Code limitation)
- `~/.claude.json` is relocated to `~/.claude-contained/.claude.json` (with symlink at original location) to work around Apple Containers' inability to bind-mount individual files. Deleting `~/.claude-contained/` will lose credentials.
- Running `claude-contained` and regular `claude` simultaneously is not recommended (both access same config via different paths)
