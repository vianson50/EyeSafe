#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# build_apk.sh — Build APK release AVEC le backend Supabase.
#
# Sans ces dart-defines, l'APK démarre en MODE DÉMO :
# pas de page de connexion, donc pas de comptes client/technicien
# et rien à déconnecter.
#
# Usage : ./build_apk.sh [--split]
#   --split  → un APK par architecture (plus léger à installer)
# ═══════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")"

DEFINES_FILE="supabase_defines.json"
if [ ! -f "$DEFINES_FILE" ]; then
  echo "❌ $DEFINES_FILE introuvable." >&2
  exit 1
fi

URL=$(python3 -c "import json;print(json.load(open('$DEFINES_FILE'))['SUPABASE_URL'])")
KEY=$(python3 -c "import json;print(json.load(open('$DEFINES_FILE'))['SUPABASE_ANON_KEY'])")

if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "❌ SUPABASE_URL / SUPABASE_ANON_KEY vides dans $DEFINES_FILE." >&2
  exit 1
fi

echo " Backend : $URL"

ARGS=(
  --dart-define="SUPABASE_URL=$URL"
  --dart-define="SUPABASE_ANON_KEY=$KEY"
)

if [ "${1:-}" = "--split" ]; then
  flutter build apk --split-per-abi "${ARGS[@]}"
else
  flutter build apk "${ARGS[@]}"
fi
