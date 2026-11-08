#!/usr/bin/env bash
# Production web build. Requires env.json (copy of env.example.json, git-ignored).
set -euo pipefail
[ -f env.json ] || { echo "env.json missing (copy env.example.json)"; exit 1; }
if grep -qi "service_role" env.json; then echo "Remove service_role keys from env.json"; exit 1; fi
flutter pub get
flutter analyze
flutter build web --release --dart-define-from-file=env.json
