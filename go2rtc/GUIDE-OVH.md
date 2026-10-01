# ═══════════════════════════════════════════════════════════
# GUIDE — Installation complète OVH + Boîtier local
#
# Architecture :
#   VPS OVH (cloud) ← tunnel WireGuard → Boîtier (site client)
#   Boîtier → enregistrement sur disque dur local
#   App → VPS pour le direct (< 1 s)
#   App → Boîtier pour le replay (ONVIF)
# ═══════════════════════════════════════════════════════════

## 1️⃣ CRÉER LE VPS OVH (10 min)

1. https://www.ovh.com/manager → **Public Cloud** → **Créer une instance**
2. Choisis :
   - Modèle : **B2-S** (2 vCPU, 4 Go RAM) — ~4 €/mois (suffisant pour 30+ flux)
   - OS : **Debian 12**
   - Région : **Gravelines** (France, proche CI)
   - Clé SSH : ajoute ta clé publique
3. Note l'**IP publique** du VPS (ex: 51.xx.xx.xx)

## 2️⃣ CONFIGURER LE VPS (15 min)

```bash
# Connexion SSH
ssh debian@51.xx.xx.xx

# Mises à jour + outils
sudo apt update && sudo apt upgrade -y
sudo apt install -y ffmpeg wireguard curl

# Télécharger go2rtc
sudo mkdir -p /opt/go2rtc
cd /opt/go2rtc
sudo curl -L https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64 -o go2rtc
sudo chmod +x go2rtc

# Copier la config
# (transfère le fichier go2rtc-vps-cloud.yaml de ce projet)
sudo cp go2rtc-vps-cloud.yaml go2rtc.yaml
# ⚠️ Change le mot de passe dans go2rtc.yaml !

# Service systemd
sudo tee /etc/systemd/system/go2rtc.service > /dev/null <<EOF
[Unit]
Description=go2rtc — VPS relais
After=network-online.target

[Service]
ExecStart=/opt/go2rtc/go2rtc
WorkingDirectory=/opt/go2rtc
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now go2rtc

# Vérifier
curl http://localhost:1984/api/streams
# Doit répondre avec {} (aucun flux pour l'instant — normal)

# Ouvrir les ports dans OVH (OpenStack / Security Group)
# → 1984/tcp (API + WebRTC)
# → 8554/tcp (RTSP pour les boîtiers)
# → 8555/udp (WebRTC)
```

## 3️⃣ CONFIGURER WIREGUARD (tunnel VPS ↔ Boîtier) (10 min)

```bash
# SUR LE VPS — génère les clés
wg genkey | sudo tee /etc/wireguard/server_private.key
sudo cat /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key

# Config WireGuard serveur
sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = $(sudo cat /etc/wireguard/server_private.key)

# Boîtier Boutique (Koumassi)
[Peer]
PublicKey = <PUBKEY_BOITIER_BOUTIQUE>
AllowedIPs = 10.0.0.2/32
EOF

sudo systemctl enable --now wg-quick@wg0
```

```bash
# SUR LE BOÎTIER (chez le client) — génère ses clés
wg genkey | sudo tee /etc/wireguard/client_private.key
sudo cat /etc/wireguard/client_private.key | wg pubkey | sudo tee /etc/wireguard/client_public.key
# Note la clé publique → colle-la dans le [Peer] du VPS ci-dessus

sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
Address = 10.0.0.2/24
PrivateKey = $(sudo cat /etc/wireguard/client_private.key)

[Peer]
PublicKey = <PUBKEY_DU_VPS>
Endpoint = 51.xx.xx.xx:51820
AllowedIPs = 10.0.0.1/32
PersistentKeepalive = 25
EOF

sudo systemctl enable --now wg-quick@wg0

# Test : le boîtier ping le VPS
ping 10.0.0.1  # doit répondre
```

## 4️⃣ CONFIGURER LE BOÎTIER LOCAL (20 min)

```bash
# SSH sur le boîtier
ssh user@IP_BOITIER

# Prérequis
sudo apt update && sudo apt install -y ffmpeg wireguard

# Monter le disque dur d'enregistrement
lsblk                          # identifie ton disque (ex: /dev/sdb1)
sudo mkfs.ext4 /dev/sdb1       # ⚠️ efface le disque — une seule fois
sudo mkdir -p /mnt/recordings
sudo mount /dev/sdb1 /mnt/recordings

# Montage automatique au boot
echo '/dev/sdb1 /mnt/recordings ext4 defaults,nofail 0 2' | \
  sudo tee -a /etc/fstab

# Installer go2rtc
sudo mkdir -p /opt/go2rtc
cd /opt/go2rtc
sudo curl -L https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64 -o go2rtc
sudo chmod +x go2rtc

# Copier la config (go2rtc-boitier-site.yaml de ce projet)
# ⚠️ Adapte les URLs RTSP de tes caméras + mot de passe !

# Copier le script d'enregistrement
# ⚠️ Adapte les URLs RTSP + rétention !
sudo cp enregistrement.sh /opt/go2rtc/
sudo chmod +x /opt/go2rtc/enregistrement.sh

# Service systemd pour go2rtc
sudo tee /etc/systemd/system/go2rtc.service > /dev/null <<EOF
[Unit]
Description=go2rtc — Boîtier local
After=network-online.target

[Service]
ExecStart=/opt/go2rtc/go2rtc
WorkingDirectory=/opt/go2rtc
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Service systemd pour l'enregistrement
sudo cp eyesafe-enregistrement.service /etc/systemd/system/

# Démarrer
sudo systemctl daemon-reload
sudo systemctl enable --now go2rtc
sudo systemctl enable --now eyesafe-enregistrement

# Vérifier
curl http://localhost:1984/api/streams
ls /mnt/recordings/BOUTIQUE-*/   # les fichiers apparaissent
```

## 5️⃣ BRANCHER L'APP SUR LE CLOUD (2 min)

Dans l'app EyeSafe :
1. **Caméras** → **Connecter un NVR** → **CLOUD (P2P)**
2. URL du cloud : `http://51.xx.xx.xx:1984`
3. Code d'appairage : `BOUTIQUE` (le préfixe des flux sur le VPS)
4. **Appairer** → les caméras apparaissent ✅

## ✅ Résultat

| Fonctionnalité | Où ça tourne | Performance |
|---|---|---|
| **Direct mobile** | VPS OVH (WebRTC) | < 1 seconde |
| **Enregistrement** | Boîtier local (disque dur) | 30 jours de rétention |
| **Replay** | Boîtier local (ONVIF) | Accès via tunnel |
| **Accès distant** | Tunnel WireGuard | Aucun port ouvert chez le client |

## 💰 Coût mensuel

| Élément | Coût |
|---|---|
| VPS OVH B2-S | ~4 €/mois (~2 600 FCFA) |
| Boîtier + disque (investissement une fois) | ~85 000 FCFA |
| **Total mensuel** | **~2 600 FCFA** pour TOUS tes clients |
