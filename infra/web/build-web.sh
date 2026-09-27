#!/usr/bin/env bash
# Release-builds the three Flutter web apps with the base path each is served under
# (/platform/, /billing/, /hrms/). The API is on the same origin, so API_BASE_URL is the
# site root unless overridden.
#   usage: infra/web/build-web.sh [API_BASE_URL]
set -euo pipefail

API_BASE_URL="${1:-/}"
cd "$(dirname "$0")/../.."

for app in platform billing hrms; do
  echo "Building $app (base /$app/)"
  (cd "apps/$app" && flutter build web --release \
      --base-href "/$app/" \
      --dart-define=API_BASE_URL="$API_BASE_URL")
  # Fail loudly on an incomplete build instead of shipping a blank app.
  for required in index.html main.dart.js assets/FontManifest.json assets/AssetManifest.bin; do
    test -f "apps/$app/build/web/$required" || { echo "missing $app/build/web/$required" >&2; exit 1; }
  done
  grep -q "<base href=\"/$app/\">" "apps/$app/build/web/index.html"
done
