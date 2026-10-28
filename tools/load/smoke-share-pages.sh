#!/usr/bin/env bash
# CI: serve share pages from the seeded Firestore emulator and run the k6
# smoke profile against them. Run inside `firebase emulators:exec` after the
# seed (FIRESTORE_EMULATOR_HOST is set there).
set -euo pipefail
cd "$(dirname "$0")/../.."
PORT=8090
(cd apps/share_pages && TENANT_FILE=../../tenants/demo-homes.json PORT=$PORT FIRESTORE_PROJECT=demo-realtor \
  dart run bin/server.dart) &
server=$!
trap 'kill $server' EXIT
for _ in $(seq 1 60); do curl -fs "localhost:$PORT/healthz" >/dev/null && break; sleep 1; done
BASE_URL="http://localhost:$PORT" PROFILE=smoke k6 run --quiet tools/load/share-pages.js
