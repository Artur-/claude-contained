# Claude Code Contained

Build container from Dockerfile
`claude-contained % container build --platform linux/arm64 -t claude-contained .`

Create volume for Claude auth/config/history (persistent)
`container volume create claude_state`

Put the `claude-contained` shell command somewhere on path, potentially aliasing to `claude`

