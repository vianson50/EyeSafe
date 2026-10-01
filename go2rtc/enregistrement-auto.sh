#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
# enregistrement-auto.sh — Enregistrement AUTOMATIQUE des caméras
#
# Ce script tourne sur le boîtier local et :
#   1. Lit les caméras depuis Supabase (comme l'app !)
#   2. Démarre un enregistrement ffmpeg par caméra détectée
#   3. Surveille les NOUVELLES caméras (recharge toutes les 5 min)
#   4. Arrête les enregistrements des caméras retirées
#   5. Purge les enregistrements > rétention
#
# → AUCUNE configuration manuelle : quand le technicien connecte
#   des caméras dans l'app, le boîtier les détecte et enregistre.
#   Quand tu retires une caméra, l'enregistrement s'arrête.
#
# Installation (une seule fois, sur chaque boîtier) :
#   chmod +x enregistrement-auto.sh
#   sudo cp enregistrement-auto.service /etc/systemd/system/
#   sudo systemctl daemon-reload
#   sudo systemctl enable --now enregistrement-auto
#
# ⚠️ Renseigne SUPABASE_URL + ANON_KEY + SITE_ID ci-dessous.
# ═══════════════════════════════════════════════════════════
set -uo pipefail

# ── Configuration (À ADAPTER PAR BOÎTIER) ─────────────────
SUPABASE_URL="https://rmhftiafvboelygsundz.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtaGZ0aWFmdmJvZWx5Z3N1bmR6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk0NzQ0MjAsImV4cCI6MjEwNTA1MDQyMH0._s9P6tJrv2DiSQdGp6rYH3rN7sc8--Twt1-qllvYjVU"
SITE_ID="2711ccb8-d629-442b-b884-a6be8e40cc2c"  # ← ID du site (table sites)

RECORD_DIR="/mnt/recordings"
SEGMENT_MINUTES=10
RETENTION_DAYS=30
CHECK_INTERVAL=300  # recharge les caméras toutes les 5 minutes
LOG_PREFIX="[enregistrement-auto]"

# ── État interne ───────────────────────────────────────────
declare -A RUNNING_PIDS   # caméra_id → PID ffmpeg
declare -A CAMERA_NAMES   # caméra_id → nom (pour les logs)

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $*"
}

# ── Récupérer les caméras depuis Supabase ─────────────────
# Retourne : "id|nom|url_rtsp" par ligne
fetch_cameras() {
  curl -sf \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
    "$SUPABASE_URL/rest/v1/equipment?site_id=eq.$SITE_ID&category=eq.camera&select=id,name,stream_url&stream_url=neq.null" \
  | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for e in data:
        url = e.get('stream_url', '')
        if url and url.startswith('rtsp://'):
            print(f\"{e['id']}|{e['name']}|{url}\")
except: pass
" 2>/dev/null || true
}

# ── Démarrer l'enregistrement d'une caméra ─────────────────
start_recording() {
  local id="$1" name="$2" url="$3"
  local dir="$RECORD_DIR/$name"
  mkdir -p "$dir"

  log "▶ DÉMARRAGE : $name ($url)"

  (
    while true; do
      local day hour
      day=$(date '+%Y-%m-%d')
      hour=$(date '+%H')
      mkdir -p "$dir/$day"

      ffmpeg -hide_banner -loglevel warning \
        -rtsp_transport tcp \
        -i "$url" \
        -c copy \
        -f segment \
        -segment_time $((SEGMENT_MINUTES * 60)) \
        -segment_format mp4 \
        -reset_timestamps 1 \
        -strftime 1 \
        "$dir/$day/%H-%M-%S.mp4" \
        2>>/dev/null

      # Caméra hors ligne / réseau coupé → retry dans 15 s.
      sleep 15
    done
  ) &

  RUNNING_PIDS[$id]=$!
  CAMERA_NAMES[$id]="$name"
}

# ── Arrêter l'enregistrement d'une caméra ──────────────────
stop_recording() {
  local id="$1"
  local pid="${RUNNING_PIDS[$id]:-}"
  local name="${CAMERA_NAMES[$id]:-inconnue}"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    log "■ ARRÊT : $name (caméra retirée de Supabase)"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  fi
  unset "RUNNING_PIDS[$id]"
  unset "CAMERA_NAMES[$id]"
}

# ── Purger les anciens enregistrements ────────────────────
purge_old() {
  log "🧹 Purge des enregistrements > $RETENTION_DAYS jours"
  find "$RECORD_DIR" -name "*.mp4" -mtime +$RETENTION_DAYS -delete 2>/dev/null
  find "$RECORD_DIR" -type d -name "20*" -empty -delete 2>/dev/null
}

# ── Boucle principale ──────────────────────────────────────
log "Démarrage — site $SITE_ID"
log "Disque : $RECORD_DIR"
mkdir -p "$RECORD_DIR"
purge_old

while true; do
  # Charge les caméras actuelles depuis Supabase.
  CURRENT=$(fetch_cameras)
  CURRENT_IDS=$(echo "$CURRENT" | cut -d'|' -f1 | grep -v '^$' || true)

  # 1. Arrête les caméras qui n'existent plus dans Supabase.
  for id in "${!RUNNING_PIDS[@]}"; do
    if ! echo "$CURRENT_IDS" | grep -q "^$id$"; then
      stop_recording "$id"
    fi
  done

  # 2. Démarre les nouvelles caméras.
  while IFS='|' read -r id name url; do
    [ -z "$id" ] && continue
    if [ -z "${RUNNING_PIDS[$id]:-}" ]; then
      start_recording "$id" "$name" "$url"
    fi
  done <<< "$CURRENT"

  ACTIVE=${#RUNNING_PIDS[@]}
  log "Caméras actives : $ACTIVE (prochaine vérification dans $((CHECK_INTERVAL / 60)) min)"

  sleep "$CHECK_INTERVAL"
done
