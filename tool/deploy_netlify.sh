#!/usr/bin/env bash
#
# Build and publish the web app to Netlify.
#
#   bash tool/deploy_netlify.sh
#
# First run needs the CLI and one interactive login:
#   npx netlify-cli login
#   npx netlify-cli sites:create      # or let the deploy below prompt you
#
# After that this script is repeatable — it rebuilds, checks the deploy
# metadata actually shipped, and publishes to production.

set -euo pipefail

cd "$(dirname "$0")/.."

FLUTTER="${FLUTTER:-flutter}"
if ! command -v "$FLUTTER" >/dev/null 2>&1; then
  FLUTTER="$HOME/flutter/bin/flutter"
fi

echo "==> Building web release"
"$FLUTTER" build web --release

# Netlify reads _redirects and _headers from the publish root. Both come from
# web/ and are copied by the Flutter build — but if that ever stops happening,
# the deploy would silently ship without the SPA rewrite and every deep link
# would 404. Fail loudly instead.
for file in _redirects _headers; do
  if [ ! -f "build/web/$file" ]; then
    echo "ERROR: build/web/$file is missing — the SPA rewrite would not apply." >&2
    exit 1
  fi
done

# Presence is not enough. A rule whose destination wraps onto the next line
# parses as a rule with no destination: the CLI calls it a syntax error and
# Netlify drops it, so every deep link 404s while the deploy still reports
# success. Require the rewrite to be one complete line.
if ! grep -Eq '^[[:space:]]*/\*[[:space:]]+/index\.html([[:space:]]+[0-9]{3})?[[:space:]]*$' \
    build/web/_redirects; then
  echo "ERROR: build/web/_redirects has no complete single-line SPA rule." >&2
  echo "       Expected a line like: /*    /index.html   200" >&2
  exit 1
fi

echo
echo "==> Publishing to Netlify (production)"
exec npx --yes netlify-cli deploy --prod --dir=build/web
