#!/usr/bin/env bash
# Full local/containers CI pipeline. Mirrors .github/workflows/ci.yml.
# Usage: tool/ci.sh [--skip-apk]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }

step "Resolve workspace"
flutter pub get

step "Codegen (Drift)"
if grep -q build_runner packages/data/pubspec.yaml; then
  (cd packages/data && dart run build_runner build --delete-conflicting-outputs)
fi

step "Format check"
dart format --output=none --set-exit-if-changed .

step "Analyze"
dart analyze --fatal-infos .

step "Tests"
failed=()
while IFS= read -r dir; do
  pkg="$(dirname "$dir")"
  echo "── $pkg"
  if ! (cd "$pkg" && flutter test --no-pub); then failed+=("$pkg"); fi
done < <(find apps packages -type d -name test -not -path '*/build/*' -not -path '*/.dart_tool/*' | sort)
if ((${#failed[@]})); then
  echo "Tests failed in: ${failed[*]}" >&2
  exit 1
fi

step "Docs site"
dart run tool/sync_docs.dart
(cd apps/docs && flutter build web --release --no-pub)

if [[ "${1:-}" != "--skip-apk" ]]; then
  step "Android debug APK"
  (cd apps/scanner && flutter build apk --debug --no-pub)
  if [[ -d /out ]]; then cp apps/scanner/build/app/outputs/flutter-apk/*.apk /out/; fi
fi

step "All green"
