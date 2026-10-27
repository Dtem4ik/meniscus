#!/bin/bash
# Pull the latest commits, build Meniscus and relaunch it. For day-to-day development:
#
#   scripts/run.sh                 # current branch
#   scripts/run.sh some-branch     # switch to another branch first
#   scripts/run.sh --no-pull       # build what is checked out
#   scripts/run.sh --debug         # Debug configuration (slower UI, better debugging)
#
# Needs Xcode 27 and XcodeGen (brew install xcodegen). Locally built apps are not quarantined,
# so there is no Gatekeeper prompt.
set -euo pipefail
cd "$(dirname "$0")/.."

pull=true
configuration=Release
branch=""
for arg in "$@"; do
  case "$arg" in
    --no-pull) pull=false ;;
    --debug) configuration=Debug ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) branch="$arg" ;;
  esac
done

command -v xcodegen >/dev/null || { echo "XcodeGen is missing: brew install xcodegen" >&2; exit 1; }

if $pull; then
  branch=${branch:-$(git rev-parse --abbrev-ref HEAD)}
  git fetch --quiet origin "$branch"
  git checkout --quiet "$branch"
  git merge --quiet --ff-only "origin/$branch"
fi
echo "Building $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD) ($configuration)…"

xcodegen generate --quiet
xcodebuild build -quiet \
  -project Meniscus.xcodeproj \
  -scheme Meniscus \
  -configuration "$configuration" \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  ONLY_ACTIVE_ARCH=YES

app="build/DerivedData/Build/Products/$configuration/Meniscus.app"
pkill -x Meniscus 2>/dev/null && sleep 0.5 || true
open "$app"
echo "Running $app"
