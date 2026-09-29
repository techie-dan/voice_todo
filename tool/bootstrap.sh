#!/usr/bin/env bash
#
# One-time bootstrap for the Voice To-Do project.
#
#   bash tool/bootstrap.sh
#
# Generates the platform folders, installs dependencies, and runs the quality
# gates. Safe to re-run: `flutter create` is invoked without --overwrite, so the
# hand-written lib/, test/, pubspec.yaml and config in this repo are preserved.

set -euo pipefail

cd "$(dirname "$0")/.."

# Fall back to the default install location if flutter is not on PATH.
FLUTTER="${FLUTTER:-flutter}"
if ! command -v "$FLUTTER" >/dev/null 2>&1; then
  FLUTTER="$HOME/flutter/bin/flutter"
fi

echo "==> Using $("$FLUTTER" --version | head -1)"

echo
echo "==> Generating platform folders (web, android, ios)"
"$FLUTTER" create \
  --project-name voice_todo \
  --org com.danieltech \
  --platforms=web,android,ios \
  .

echo
echo "==> Installing dependencies"
if ! "$FLUTTER" pub get; then
  echo "==> Resolution failed; re-adding packages to pick up current versions"
  "$FLUTTER" pub add shared_preferences speech_to_text
fi

# Run the remaining gates even if one fails, so a single run shows everything.
status=0
gate() {
  local label="$1"; shift
  echo
  echo "==> $label"
  "$@" || status=1
}

gate "Analyzing" "$FLUTTER" analyze
gate "Testing" "$FLUTTER" test
gate "Building web release" "$FLUTTER" build web --release

echo
if [ "$status" -eq 0 ]; then
  echo "All gates passed."
  echo "  Run locally:  $FLUTTER run -d chrome"
  echo "  Web build:    build/web"
else
  echo "One or more gates failed — see the output above."
fi

exit "$status"
