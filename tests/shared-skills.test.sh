#!/usr/bin/env bash
# Exercise both launchers without a container runtime or changes to the real HOME.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

for launcher in claude-contained claude-docked; do
  fixture="$test_root/$launcher"
  mkdir -p "$fixture/private/alpha" "$fixture/public/beta" "$fixture/project"
  mkdir -p "$fixture/public/.git" "$fixture/public/.system" "$fixture/external skill"
  printf 'private\n' > "$fixture/private/alpha/SKILL.md"
  printf 'public\n' > "$fixture/public/beta/SKILL.md"
  printf 'metadata\n' > "$fixture/public/README.md"
  printf 'external\n' > "$fixture/external skill/SKILL.md"
  ln -s "$fixture/external skill" "$fixture/public/linked skill"
  env HOME="$fixture" CLAUDE_CONTAINED_LIB_ONLY=1 bash -s -- "$repo/$launcher" "$fixture" <<'SUITE'
set -euo pipefail
launcher="$1"
fixture="$2"
source "$launcher" '--share-skills=~/private' '--share-skills=~/public' "$fixture/project"
[[ "${share_skills_dirs[0]}" == "$fixture/private" ]]
[[ "${share_skills_dirs[1]}" == "$fixture/public" ]]
container_argv=()
prepare_shared_skills
[[ "$share_skills_dir" == "$fixture/private" ]]
[[ ${#shared_skill_names[@]} -eq 2 ]]
for tool in claude codex agents copilot gemini vibe; do
  add_shared_skills_mount "$fixture/.$tool/skills" "$fixture/.$tool"
done
[[ ${#container_argv[@]} -eq 36 ]]
for ((offset=0; offset<36; offset+=6)); do
  [[ "${container_argv[$((offset+1))]}" == "type=bind,src=$fixture/private,dst="* ]]
  [[ "${container_argv[$((offset+3))]}" == "type=bind,src=$fixture/public/beta,dst="*"/skills/beta" ]]
  [[ "${container_argv[$((offset+5))]}" == "type=bind,src=$fixture/external skill,dst="*"/skills/linked skill" ]]
done
# Check write routing using the generated bind-mount specifications. The most
# specific destination wins; actual mounting is left to the container runtime.
source_for_container_path() {
  local path="$1" spec src dst best="" result=""
  for spec in "${container_argv[@]}"; do
    [[ "$spec" == type=bind,* ]] || continue
    src="${spec#type=bind,src=}"
    src="${src%%,dst=*}"
    dst="${spec##*,dst=}"
    if [[ "$path" == "$dst" || "$path" == "$dst/"* ]] && [[ ${#dst} -gt ${#best} ]]; then
      best="$dst"
      result="$src${path#"$dst"}"
    fi
  done
  [[ -n "$result" ]]
  printf '%s\n' "$result"
}
for tool in claude codex agents copilot gemini vibe; do
  new_dir="$(source_for_container_path "$fixture/.$tool/skills/new-$tool")"
  mkdir "$new_dir"
  printf 'new\n' > "$new_dir/SKILL.md"
  [[ -f "$fixture/private/new-$tool/SKILL.md" ]]
  [[ ! -e "$fixture/public/new-$tool" ]]
done
public_skill="$(source_for_container_path "$fixture/.claude/skills/beta/SKILL.md")"
printf 'edited\n' > "$public_skill"
[[ "$(cat "$fixture/public/beta/SKILL.md")" == edited ]]
[[ -d "$fixture/private/beta" && ! -L "$fixture/private/beta" ]]
dir_is_empty "$fixture/private/beta"
# A restart accepts the empty mountpoints and preserves the new primary skills.
prepare_shared_skills
[[ -f "$share_skills_dir/new-claude/SKILL.md" ]]
[[ ${#shared_skill_names[@]} -eq 2 ]]
# Summary names sources and every actual target, with a clear default and no hash.
container_argv=()
for tool in claude codex agents copilot gemini vibe; do
  add_shared_skills_mount "$fixture/.$tool/skills" "$fixture/.$tool"
done
summary="$(show_shared_skills_summary 2>&1)"
[[ "$summary" == 'Skills: [~/private (new skills here), ~/public] -> [~/.claude/skills, ~/.codex/skills, ~/.agents/skills, ~/.copilot/skills, ~/.gemini/skills, ~/.vibe/skills]' ]]
# Never hide user data, including dangling symlinks inside otherwise empty dirs.
printf 'keep\n' > "$fixture/private/beta/user-file"
if prepare_shared_skills 2> "$fixture/error"; then exit 1; else [[ $? -eq 2 ]]; fi
[[ "$(cat "$fixture/private/beta/user-file")" == keep ]]
rm "$fixture/private/beta/user-file"
ln -s nonexistent "$fixture/private/beta/.broken"
if prepare_shared_skills 2> "$fixture/error"; then exit 1; else [[ $? -eq 2 ]]; fi
rm "$fixture/private/beta/.broken"
rmdir "$fixture/private/beta"
ln -s nonexistent "$fixture/private/beta"
if prepare_shared_skills 2> "$fixture/error"; then exit 1; else [[ $? -eq 2 ]]; fi
rm "$fixture/private/beta"
printf 'keep\n' > "$fixture/private/beta"
if prepare_shared_skills 2> "$fixture/error"; then exit 1; else [[ $? -eq 2 ]]; fi
rm "$fixture/private/beta"
# Duplicate names across later sources are rejected too.
mkdir -p "$fixture/third/beta"
printf 'third\n' > "$fixture/third/beta/SKILL.md"
share_skills_dirs+=("$fixture/third")
if prepare_shared_skills 2> "$fixture/error"; then exit 1; else [[ $? -eq 2 ]]; fi
[[ "$(cat "$fixture/error")" == *"duplicate shared skill directory 'beta'"* ]]
# Changing order changes the destination for new skills.
mkdir -p "$fixture/private/beta"
share_skills_dirs=("$fixture/public" "$fixture/private")
prepare_shared_skills
[[ "$share_skills_dir" == "$fixture/public" ]]
# Single-source and no-source behavior remain supported.
share_skills_dirs=("$fixture/private")
container_argv=()
prepare_shared_skills
[[ ${#shared_skill_names[@]} -eq 0 ]]
add_shared_skills_mount "$fixture/tool/skills" "$fixture/tool"
[[ ${#container_argv[@]} -eq 2 ]]
[[ "${container_argv[1]}" == "type=bind,src=$fixture/private,dst=$fixture/tool/skills" ]]
share_skills_dirs=()
prepare_shared_skills
[[ -z "$share_skills_dir" ]]
SUITE
  # Every provided source must be validated, not just the last flag.
  if env HOME="$fixture" CLAUDE_CONTAINED_LIB_ONLY=1 bash "$repo/$launcher" \
    '--share-skills=~/missing' '--share-skills=~/public' "$fixture/project" > "$fixture/output" 2>&1; then
    echo 'FAIL: missing first source accepted'; exit 1
  else
    [[ $? -eq 2 ]]
  fi
  if env HOME="$fixture" CLAUDE_CONTAINED_LIB_ONLY=1 bash "$repo/$launcher" \
    --share-skills= "$fixture/project" > "$fixture/output" 2>&1; then
    echo 'FAIL: empty source accepted'; exit 1
  else
    [[ $? -eq 2 ]]
  fi
  echo "PASS: $launcher shared skills"
done
