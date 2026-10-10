#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s "short feature name"\n' "$0" >&2
  exit 2
fi

title="$1"
slug="$(printf '%s' "$title" | LC_ALL=C tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
[[ -n "$slug" ]] || { printf 'Feature name must contain letters or numbers.\n' >&2; exit 2; }

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'Run this script from inside the project git repository.\n' >&2
  exit 2
}
cd "$root"
mkdir -p features
file="features/${slug}.md"
[[ ! -e "$file" ]] || { printf 'Feature file already exists: %s\n' "$file" >&2; exit 1; }

cat > "$file" <<EOF
# $title

## Goal
What should become possible for the person using the project?

## Acceptance checks
- [ ] Describe one observable result.
- [ ] Describe how to verify it locally without AWS.

## Change
- Component:
- Files likely involved:

## Test

\`\`\`sh
# Put the exact local command here.
\`\`\`

## Done when
- [ ] Acceptance checks pass.
- [ ] Relevant tests pass.
- [ ] No AWS resources were created unless explicitly needed.
EOF

git add -N -- "$file"
printf 'Created %s. Edit the draft shown by: git diff -- %s\n' "$file" "$file"