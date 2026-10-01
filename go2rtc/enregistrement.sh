#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
# enregistrement.sh — Enregistrement continu des caméras
# sur disque dur local (segments de 10 minutes par caméra).
#
# Installation sur le boîtier :
#   chmod +x enregistrement.sh
#   ./enregistrement.sh &   (ou via systemd, voir en bas)
#
# Prérequis :
#   - ffmpeg installé : apt install ffmpeg
#   - Disque monté : /mnt/recordings
#   - Les dossiers sont créés automatiquement
# ═══════════════════════════════════════════════════════════
set -euo pipefail

# ── Configuration ──────────────────────────────────────────
RECORD_DIR="/mnt/recordings"
SEGMENT_MINUTES=10          # durée d'un fichier
RETENTION_DAYS=30           # purge au-delà de 30 jours
CAMERAS=(
  # "nom|url_rtsp"
  "BOUTIQUE-1|rtsp://admin:MotDePasse@192.168.100.72:554/cam/realmonitor?channel=1&subtype=0"
  "BOUTIQUE-2|rtsp://admin:MotDePasse@192.168.100.72:554/cam/realmonitor?channel=2&subtype=0"
  "BOUTIQUE-3|rtsp://admin:MotDePasse@192.168.100.72:554/cam/realmonitor?channel=3&subtype=0"
  "BOUTIQUE-4|rtsp://admin:MotDePasse@192.168.100.72:554/cam/realmonitor?channel=4&subtype=0"
)

# ── Fonction : enregistrer une caméra ─────────────────────
record_camera() {
  local name="$1"
  local url="$2"
  local dir="$RECORD_DIR/$name"

  mkdir -p "$dir"

  echo "[$(date '+%H:%M:%S')] Démarrage enregistrement : $name"

  while true; do
    local day
    day=$(date '+%Y-%m-%d')
    local hour
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
      2>&1 | while read -r line; do
        echo "  [$name] $line"
      done

    # ffmpeg s'est arrêté (caméra hors ligne, réseau coupé) —
    # on réessaie dans 10 secondes.
    echo "[$(date '+%H:%M:%S')] $name : connexion perdue — retry dans 10 s"
    sleep 10
  done
}

# ── Fonction : purger les anciens enregistrements ─────────
purge_old() {
  echo "[$(date '+%H:%M:%S')] Purge des enregistrements > $RETENTION_DAYS jours"
  find "$RECORD_DIR" -name "*.mp4" -mtime +$RETENTION_DAYS -delete
  # Supprime aussi les dossiers jours vides.
  find "$RECORD_DIR" -type d -name "20*" -empty -delete 2>/dev/null || true
}

# ── Démarrage ─────────────────────────────────────────────
mkdir -p "$RECORD_DIR"
purge_old

for cam in "${CAMERAS[@]}"; do
  IFS='|' read -r name url <<< "$cam"
  record_camera "$name" "$url" &
  sleep 2  # décale les démarrages (évite le hammering réseau)
done

# Purge quotidienne (à 03:00)
while true; do
  sleep $((24 * 3600))
  purge_old
done

# Tous les enregistrements tournent en arrière-plan.
wait
