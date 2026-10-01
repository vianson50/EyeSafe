#!/bin/bash
# ═══════════════════════════════════════════════════════════
# install-boitier.sh — Installation AUTOMATIQUE du boîtier go2rtc
#
# CE SCRIPT FAIT TOUT EN UNE SEULE COMMANDE :
#   ✅ Installe go2rtc + ffmpeg + les services
#   ✅ Configure le disque dur d'enregistrement
#   ✅ Lit les caméras depuis Supabase (automatique)
#   ✅ Démarre tout (redémarre seul après coupure)
#
# USAGE SUR LE BOÎTIER (copier-coller UNE seule commande) :
#   curl -fsSL https://raw.githubusercontent.com/vianson50/EyeSafe/main/go2rtc/install-boitier.sh | bash -s -- --site=UUID_DU_SITE
#
# OU (si pas d'accès GitHub) :
#   scp go2rtc/install-boitier.sh user@IP_BOITIER:/tmp/
#   ssh user@IP_BOITIER "chmod +x /tmp/install-boitier.sh && /tmp/install-boitier.sh --site=UUID"
# ═══════════════════════════════════════════════════════════
set -euo pipefail

# ── Couleurs pour lisibilité ───────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo "══════════════════════════════════════════════════════"
echo "  INSTALLATION BOÎTIER EYESAFE — go2rtc + enregistrement"
echo "══════════════════════════════════════════════════════"
echo ""

# ── Parse les arguments ────────────────────────────────────
SITE_ID=""
SUPABASE_URL="https://rmhftiafvboelygsundz.supabase.co"
SUPABASE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtaGZ0aWFmdmJvZWx5Z3N1bmR6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk0NzQ0MjAsImV4cCI6MjEwNTA1MDQyMH0._s9P6tJrv2DiSQdGp6rYH3rN7sc8--Twt1-qllvYjVU"
CLOUD_URL=""
CLOUD_USER=""
CLOUD_PASS=""

for arg in "$@"; do
  case $arg in
    --site=*)    SITE_ID="${arg#*=}" ;;
    --cloud=*)   CLOUD_URL="${arg#*=}" ;;
    --cloud-user=*) CLOUD_USER="${arg#*=}" ;;
    --cloud-pass=*) CLOUD_PASS="${arg#*=}" ;;
  esac
done

[ -z "$SITE_ID" ] && error "Usage : ./install-boitier.sh --site=UUID_DU_SITE (voir Supabase → sites → id)"

info "Site : $SITE_ID"

# ── 1. Vérifications préalables ────────────────────────────
echo ""
echo "── Étape 1/6 : Vérifications ──"

# Système Linux ?
[ "$(uname -s)" != "Linux" ] && error "Ce script doit tourner sur Linux (Debian/Ubuntu)"

# Accès internet ?
if ! curl -sf --max-time 5 https://google.com > /dev/null 2>&1; then
  error "Pas d'accès internet — vérifie le câble Ethernet au routeur"
fi
info "Internet : OK"

# Root ou sudo ?
if [ "$(id -u)" -ne 0 ]; then
  if ! sudo -n true 2>/dev/null; then
    warn "Ce script a besoin des droits root (sudo)"
    warn "Relance avec : sudo $0 $*"
    exit 1
  fi
  SUDO="sudo"
else
  SUDO=""
fi

# ── 2. Installation des outils ─────────────────────────────
echo ""
echo "── Étape 2/6 : Installation des outils (2-3 min) ──"

$SUDO apt-get update -qq
$SUDO apt-get install -y -qq ffmpeg curl python3 wget 2>/dev/null
info "ffmpeg + curl + python3 : installés"

# ── 3. Télécharge et installe go2rtc ───────────────────────
echo ""
echo "── Étape 3/6 : Installation de go2rtc ──"

$SUDO mkdir -p /opt/go2rtc
cd /opt/go2rtc

if [ ! -f go2rtc ]; then
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)  GO2RTC_URL="https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64" ;;
    aarch64) GO2RTC_URL="https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_arm64" ;;
    armv7l)  GO2RTC_URL="https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_arm" ;;
    *)       error "Architecture non supportée : $ARCH" ;;
  esac

  $SUDO wget -q "$GO2RTC_URL" -O go2rtc
  $SUDO chmod +x go2rtc
  info "go2rtc téléchargé ($ARCH)"
else
  info "go2rtc déjà présent"
fi

# ── 4. Configure le disque dur ────────────────────────────
echo ""
echo "── Étape 4/6 : Configuration du disque dur ──"

# Cherche un disque USB non monté
DISK=$(lsblk -rno NAME,TYPE,SIZE,MOUNTPOINT | grep 'disk' | \
  awk '$4 == "" && $3 ~ /^[0-9.]+T/' | head -1 | awk '{print $1}')

if [ -n "$DISK" ]; then
  info "Disque dur détecté : /dev/$DISK"

  # Demande confirmation avant formatage
  echo ""
  warn "⚠️  LE DISQUE /dev/$DISK VA ÊTRE FORMATÉ (toutes les données seront effacées)"
  read -p "Continuer ? (oui/non) : " CONFIRM
  [ "$CONFIRM" != "oui" ] && warn "Disque non formaté — enregistrement sur /opt/recordings (espace système)" && DISK=""

  if [ -n "$DISK" ]; then
    $SUDO wipefs -a "/dev/$DISK"
    $SUDO mkfs.ext4 -F "/dev/$DISK" 2>/dev/null
    $SUDO mkdir -p /mnt/recordings
    $SUDO mount "/dev/$DISK" /mnt/recordings

    # Montage automatique au boot
    UUID=$(blkid -s UUID -o value "/dev/$DISK")
    echo "UUID=$UUID /mnt/recordings ext4 defaults,nofail 0 2" | \
      $SUDO tee -a /etc/fstab > /dev/null
    info "Disque formaté et monté sur /mnt/recordings"
    info "Montage automatique configuré (UUID=$UUID)"
  fi
else
  warn "Pas de disque USB détecté — enregistrement sur /opt/recordings (espace système)"
  $SUDO mkdir -p /opt/recordings
  RECORD_DIR="/opt/recordings"
fi

RECORD_DIR="${RECORD_DIR:-/mnt/recordings}"
$SUDO mkdir -p "$RECORD_DIR"

# ── 5. Crée les scripts de service ────────────────────────
echo ""
echo "── Étape 5/6 : Configuration des services ──"

# go2rtc.yaml (config minimale — les flux viennent de Supabase)
$SUDO tee /opt/go2rtc/go2rtc.yaml > /dev/null << EOF
api:
  listen: ":1984"
  username: eyesafe
  password: Boitier-\$(hostname)-2026!

rtsp:
  listen: ":8554"

ffmpeg:
  bin: /usr/bin/ffmpeg
EOF
info "go2rtc.yaml créé"

# enregistrement-auto.sh (lit les caméras depuis Supabase)
$SUDO tee /opt/go2rtc/enregistrement-auto.sh > /dev/null << 'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail

SUPABASE_URL="__SUPABASE_URL__"
SUPABASE_ANON_KEY="__SUPABASE_KEY__"
SITE_ID="__SITE_ID__"
RECORD_DIR="__RECORD_DIR__"
SEGMENT_MINUTES=10
RETENTION_DAYS=30
CHECK_INTERVAL=300

declare -A RUNNING_PIDS
declare -A CAMERA_NAMES

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [rec] $*"; }

fetch_cameras() {
  curl -sf \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
    "$SUPABASE_URL/rest/v1/equipment?site_id=eq.$SITE_ID&category=eq.camera&select=id,name,stream_url&stream_url=neq.null" \
  | python3 -c "
import json, sys
try:
    for e in json.load(sys.stdin):
        url = e.get('stream_url', '')
        if url and url.startswith('rtsp://'):
            print(f\"{e['id']}|{e['name']}|{url}\")
except: pass
" 2>/dev/null || true
}

start_recording() {
  local id="$1" name="$2" url="$3"
  local dir="$RECORD_DIR/$name"
  mkdir -p "$dir"
  log "▶ $name"

  (
    while true; do
      local day=$(date '+%Y-%m-%d')
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
        "$dir/$day/%H-%M-%S.mp4" 2>/dev/null
      sleep 15
    done
  ) &
  RUNNING_PIDS[$id]=$!
  CAMERA_NAMES[$id]="$name"
}

stop_recording() {
  local id="$1"
  local pid="${RUNNING_PIDS[$id]:-}"
  [ -n "$pid" ] && kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null
  unset "RUNNING_PIDS[$id]" "CAMERA_NAMES[$id]"
}

purge_old() {
  log "🧹 Purge > $RETENTION_DAYS jours"
  find "$RECORD_DIR" -name "*.mp4" -mtime +$RETENTION_DAYS -delete 2>/dev/null
  find "$RECORD_DIR" -type d -name "20*" -empty -delete 2>/dev/null
}

log "Démarrage — site $SITE_ID"
mkdir -p "$RECORD_DIR"
purge_old

while true; do
  CURRENT=$(fetch_cameras)
  CURRENT_IDS=$(echo "$CURRENT" | cut -d'|' -f1 | grep -v '^$' || true)

  for id in "${!RUNNING_PIDS[@]}"; do
    echo "$CURRENT_IDS" | grep -q "^$id$" || stop_recording "$id"
  done

  while IFS='|' read -r id name url; do
    [ -z "$id" ] && continue
    [ -z "${RUNNING_PIDS[$id]:-}" ] && start_recording "$id" "$name" "$url"
  done <<< "$CURRENT"

  log "Caméras actives : ${#RUNNING_PIDS[@]}"
  sleep "$CHECK_INTERVAL"
done
SCRIPT

# Remplace les placeholders
$SUDO sed -i \
  "s|__SUPABASE_URL__|$SUPABASE_URL|; s|__SUPABASE_KEY__|$SUPABASE_KEY|; s|__SITE_ID__|$SITE_ID|; s|__RECORD_DIR__|$RECORD_DIR|" \
  /opt/go2rtc/enregistrement-auto.sh
$SUDO chmod +x /opt/go2rtc/enregistrement-auto.sh
info "enregistrement-auto.sh créé"

# Service systemd pour go2rtc
$SUDO tee /etc/systemd/system/go2rtc.service > /dev/null << EOF
[Unit]
Description=go2rtc — Boîtier EyeSafe
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/go2rtc/go2rtc
WorkingDirectory=/opt/go2rtc
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Service systemd pour l'enregistrement
$SUDO tee /etc/systemd/system/eyesafe-rec.service > /dev/null << EOF
[Unit]
Description=EyeSafe — Enregistrement auto des caméras
After=network-online.target go2rtc.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/go2rtc/enregistrement-auto.sh
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal
SyslogIdentifier=eyesafe-rec

[Install]
WantedBy=multi-user.target
EOF

# Active les services
$SUDO systemctl daemon-reload
$SUDO systemctl enable --now go2rtc
$SUDO systemctl enable --now eyesafe-rec
info "Services go2rtc + eyesafe-rec activés (redémarrage automatique)"

# ── 6. Résumé final ───────────────────────────────────────
echo ""
echo "── Étape 6/6 : Vérification ──"
sleep 3

if $SUDO systemctl is-active --quiet go2rtc; then
  info "go2rtc : ✅ actif sur http://$(hostname -I | awk '{print $1}'):1984"
else
  warn "go2rtc n'est pas encore actif — vérifie : journalctl -u go2rtc -n 20"
fi

if $SUDO systemctl is-active --quiet eyesafe-rec; then
  info "Enregistrement : ✅ actif"
  $SUDO journalctl -u eyesafe-rec -n 5 --no-pager | tail -3
else
  warn "Enregistrement pas encore actif — vérifie : journalctl -u eyesafe-rec -n 20"
fi

echo ""
echo "══════════════════════════════════════════════════════"
echo "  ✅ INSTALLATION TERMINÉE !"
echo "══════════════════════════════════════════════════════"
echo ""
echo "  📹 Boîtier   : $(hostname -I | awk '{print $1}')"
echo "  🌐 Interface : http://$(hostname -I | awk '{print $1}'):1984"
echo "  💾 Enregistrement : $RECORD_DIR"
echo "  🔄 Caméras  : lues automatiquement depuis Supabase"
echo ""
echo "  Le boîtier détecte les caméras dans les 5 minutes."
echo "  Quand tu en ajoutes dans l'app → il les enregistre tout seul."
echo "  Quand tu en retires → il arrête tout seul."
echo ""
echo "  → Tu peux maintenant débrancher l'écran et le clavier."
echo "  → Le boîtier tourne 24/7 sans intervention."
echo "══════════════════════════════════════════════════════"
