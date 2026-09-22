#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# EYESAFE — Création des comptes réels (client + technicien)
# via l'Admin API Supabase.
#
# Usage minimal (l'URL est lue depuis supabase_defines.json) :
#   SUPABASE_SERVICE_ROLE_KEY=eyJ... ./supabase/create_users.sh \
#       --client-email client@entreprise.ci \
#       --tech-email tech@eyesafe.ci
#
# Options :
#   --client-email / --tech-email      emails des comptes (requis*)
#   --client-password / --tech-password  sinon générés aléatoirement
#   --client-name / --tech-name        noms affichés
#   --no-promote                       ne pas promouvoir le rôle technicien
#
# * Sans emails explicites : valeurs par défaut client@eyesafe.dev /
#   technicien@eyesafe.dev (comptes de test).
#
# 🔑 Clé service_role : Dashboard Supabase → Project Settings →
#    API → service_role secret. Elle donne un accès TOTAL à la base :
#    ne la commit jamais, ne la mets jamais dans l'app Flutter.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."

# ── Configuration ─────────────────────────────────────────────
DEFINES_FILE="supabase_defines.json"
if [ ! -f "$DEFINES_FILE" ]; then
  echo "❌ $DEFINES_FILE introuvable à la racine du projet." >&2
  exit 1
fi

URL=$(python3 -c "import json;print(json.load(open('$DEFINES_FILE'))['SUPABASE_URL'])")
KEY="${SUPABASE_SERVICE_ROLE_KEY:-${SERVICE_ROLE_KEY:-}}"

CLIENT_EMAIL="${CLIENT_EMAIL:-}"
TECH_EMAIL="${TECH_EMAIL:-}"
CLIENT_PASSWORD="${CLIENT_PASSWORD:-}"
TECH_PASSWORD="${TECH_PASSWORD:-}"
CLIENT_NAME="Client"
TECH_NAME="Technicien"
PROMOTE=1

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --client-email)    CLIENT_EMAIL="$2";    shift 2 ;;
    --tech-email)      TECH_EMAIL="$2";      shift 2 ;;
    --client-password) CLIENT_PASSWORD="$2"; shift 2 ;;
    --tech-password)   TECH_PASSWORD="$2";   shift 2 ;;
    --client-name)     CLIENT_NAME="$2";     shift 2 ;;
    --tech-name)       TECH_NAME="$2";       shift 2 ;;
    --no-promote)      PROMOTE=0;            shift ;;
    -h|--help)         usage ;;
    *) echo "Argument inconnu : $1" >&2; usage 1 ;;
  esac done

# Défauts de test (si aucun email fourni).
CLIENT_EMAIL="${CLIENT_EMAIL:-client@eyesafe.dev}"
TECH_EMAIL="${TECH_EMAIL:-technicien@eyesafe.dev}"

if [ -z "$KEY" ]; then
  cat >&2 <<EOF
❌ Clé service_role manquante.

Exportez-la avant de lancer le script :
  SUPABASE_SERVICE_ROLE_KEY=eyJ... ./supabase/create_users.sh ...

Où la trouver : Dashboard Supabase → Project Settings → API →
service_role secret (⚠️ accès TOTAL — à ne jamais commit).
EOF
  exit 1
fi

# ── Helpers ───────────────────────────────────────────────────
gen_password() {
  # 16 caractères alphanumériques + symboles sûrs.
  python3 -c "import secrets,string; \
    print(''.join(secrets.choice(string.ascii_letters + string.digits) \
    for _ in range(16)))"
}

json_field() { # json_field <fichier> <clé>
  python3 -c "import json,sys; \
    d=json.load(open('$1')); print(d.get('$2',''))" 2>/dev/null || true
}

# create_user <email> <password> <full_name>
# Affiche l'UUID sur stdout (vide si introuvable).
create_user() {
  local email="$1" password="$2" full_name="$3"
  local body=/tmp/eyesafe_user_$$.json
  local code
  code=$(curl -s -o "$body" -w "%{http_code}" \
    -X POST "$URL/auth/v1/admin/users" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"email\": \"$email\",
      \"password\": \"$password\",
      \"email_confirm\": true,
      \"user_metadata\": { \"full_name\": \"$full_name\" }
    }")

  case "$code" in
    200|201)
      echo "  ✔ créé" >&2
      json_field "$body" "id"
      ;;
    422)
      echo "  ℹ existe déjà — récupération de l'UUID…" >&2
      find_user_id "$email"
      ;;
    *)
      echo "  ✗ échec (HTTP $code) :" >&2
      cat "$body" >&2; echo >&2
      rm -f "$body"
      return 1
      ;;
  esac
  rm -f "$body"
}

# find_user_id <email> — parcourt les utilisateurs via l'Admin API.
find_user_id() {
  local email="$1"
  local body=/tmp/eyesafe_users_$$.json
  curl -s -o "$body" \
    "$URL/auth/v1/admin/users?per_page=1000" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $KEY"
  python3 - "$body" "$email" <<'PYEOF' 2>/dev/null || true
import json, sys
users = json.load(open(sys.argv[1])).get('users', [])
email = sys.argv[2]
for u in users:
    if u.get('email', '').lower() == email.lower():
        print(u['id'])
        break
PYEOF
  rm -f "$body"
}

# set_role <uuid> <role> — PATCH sur public.profiles (service_role).
set_role() {
  local uid="$1" role="$2"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PATCH "$URL/rest/v1/profiles?id=eq.$uid" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"role\": \"$role\"}")
  if [ "$code" = "204" ]; then
    echo "  ✔ rôle « $role » appliqué"
  else
    echo "  ✗ rôle non appliqué (HTTP $code) — vérifiez la migration initiale." >&2
    return 1
  fi
}

# ── Exécution ─────────────────────────────────────────────────
echo "═══ Comptes EYESAFE — $URL ═══"

# Mot de passe : fourni ou généré (affiché une seule fois).
GEN_CLIENT=0; GEN_TECH=0
if [ -z "$CLIENT_PASSWORD" ]; then CLIENT_PASSWORD=$(gen_password); GEN_CLIENT=1; fi
if [ -z "$TECH_PASSWORD" ];    then TECH_PASSWORD=$(gen_password);    GEN_TECH=1;    fi

echo "→ Client ($CLIENT_EMAIL)"
CLIENT_ID=$(create_user "$CLIENT_EMAIL" "$CLIENT_PASSWORD" "$CLIENT_NAME") || exit 1

echo "→ Technicien ($TECH_EMAIL)"
TECH_ID=$(create_user "$TECH_EMAIL" "$TECH_PASSWORD" "$TECH_NAME") || exit 1

# Promotion du technicien (rôle par défaut = client).
if [ "$PROMOTE" = "1" ] && [ -n "$TECH_ID" ]; then
  echo "→ Promotion technicien"
  set_role "$TECH_ID" "technicien" || true
fi
if [ -n "$CLIENT_ID" ]; then
  echo "→ Rôle client confirmé"
  set_role "$CLIENT_ID" "client" >/dev/null || true
fi

cat <<EOF

═══ Récapitulatif ═══
  Client     : $CLIENT_EMAIL
  Mot de passe : $CLIENT_PASSWORD$( [ "$GEN_CLIENT" = "1" ] && echo "   ← GÉNÉRÉ — noter maintenant, jamais réaffiché" )
  Technicien : $TECH_EMAIL
  Mot de passe : $TECH_PASSWORD$( [ "$GEN_TECH" = "1" ] && echo "   ← GÉNÉRÉ — noter maintenant, jamais réaffiché" )

  Emails pré-confirmés (connexion immédiate).
  Profils créés par le trigger on_auth_user_created.

Prochaines étapes :
  1. Créer le site du client (table public.sites ou via l'app).
  2. Assigner le technicien au site :
       insert into public.site_technicians (site_id, technician_id)
       select s.id, '$TECH_ID' from public.sites s
       where s.owner_id = '$CLIENT_ID';
EOF
