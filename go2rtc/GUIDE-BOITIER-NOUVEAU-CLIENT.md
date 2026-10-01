# ═══════════════════════════════════════════════════════════
# GUIDE — Ajouter un NOUVEAU CLIENT (zéro config boîtier)
#
# Grâce à enregistrement-auto.sh, le boîtier lit les caméras
# depuis Supabase TOUT SEUL. Voici le parcours complet pour
# installer chez un nouveau client :
# ═══════════════════════════════════════════════════════════

## 📋 Checklist matériel (à apporter)

| Matériel | Prix approx. |
|---|---|
| Boîtier (Beelink N100 / Android TV Box) | 10-45 000 FCFA |
| Disque dur externe USB 3.0 (WD Purple 2 To) | 35 000 FCFA |
| Câble Ethernet (relié au routeur du client) | 2 000 FCFA |

## 🔧 Installation physique (15 min)

1. **Branche le boîtier** sur le routeur du client (câble Ethernet)
2. **Branche le disque dur** sur le boîtier (USB 3.0)
3. **Branche l'alimentation** du boîtier

## 💻 Configuration du boîtier (UNE SEULE FOIS par modèle)

```bash
# SSH sur le boîtier
ssh user@IP_BOITIER

# 1. Installe les outils
sudo apt update && sudo apt install -y ffmpeg curl python3

# 2. Monte le disque dur
lsblk                          # identifie le disque (ex: /dev/sdb1)
sudo mkfs.ext4 /dev/sdb1       # ⚠️ efface le disque (une seule fois !)
sudo mkdir -p /mnt/recordings
sudo mount /dev/sdb1 /mnt/recordings

# Montage auto au boot
echo '/dev/sdb1 /mnt/recordings ext4 defaults,nofail 0 2' | \
  sudo tee -a /etc/fstab

# 3. Copie les fichiers de ce projet
# (depuis ton PC : scp go2rtc/enregistrement-auto.* user@IP_BOITIER:/tmp/)
sudo mkdir -p /opt/go2rtc
sudo cp /tmp/enregistrement-auto.sh /opt/go2rtc/
sudo cp /tmp/enregistrement-auto.service /etc/systemd/system/
sudo chmod +x /opt/go2rtc/enregistrement-auto.sh

# 4. ⚠️ ADAPTE les 3 variables dans le script :
sudo nano /opt/go2rtc/enregistrement-auto.sh
#   SUPABASE_URL     → (déjà bon)
#   SUPABASE_ANON_KEY → (déjà bon)
#   SITE_ID          → l'UUID du site du client (voir ci-dessous)

# 5. Démarre le service
sudo systemctl daemon-reload
sudo systemctl enable --now enregistrement-auto

# 6. Vérifie
sudo systemctl status enregistrement-auto
sudo journalctl -u enregistrement-auto -f
# → Doit afficher : "▶ DÉMARRAGE : Caméra 1..." pour chaque caméra
```

## 📱 Comment trouver le SITE_ID du client

```bash
# Depuis le boîtier (ou ton PC) :
curl -s -H "apikey: TA_CLE_ANON" \
  "https://rmhftiafvboelygsundz.supabase.co/rest/v1/sites?select=id,name" \
  | python3 -m json.tool
```

→ Trouve le site du client → copie son `id` (UUID).

## ✅ Résultat — le flux automatique

```
1. Le technicien installe les caméras physiquement (NVR/caméras IP)
2. Dans l'APP : Connecter un NVR → les caméras sont enregistrées
   dans Supabase
3. LE BOÎTIER DÉTECTE automatiquement (dans les 5 minutes) :
   → lit Supabase → trouve les nouvelles caméras
   → démarre un enregistrement ffmpeg par caméra
   → les fichiers apparaissent sur /mnt/recordings/CAMÉRA/JOUR/
4. Si une caméra est RETIRÉE de l'app → le boîtier arrête
   son enregistrement automatiquement
5. Tous les jours : purge des fichiers > 30 jours
```

## 📁 Structure du disque

```
/mnt/recordings/
├── Caméra 1/
│   └── 2026-10-01/
│       ├── 14-00-00.mp4    (10 minutes)
│       ├── 14-10-00.mp4
│       └── ...
├── Caméra 2/
│   └── 2026-10-01/
│       └── ...
└── Caméra 8/
    └── ...
```

## 🔄 Pour un DEUXIÈME client

1. Achète un autre boîtier + disque
2. Même installation physique (15 min)
3. Change SEULEMENT `SITE_ID` dans le script (l'UUID du 2e site)
4. `sudo systemctl restart enregistrement-auto`
5. ✅ Fini — les caméras du 2e client s'enregistrent automatiquement

## 🩺 Dépannage

| Symptôme | Solution |
|---|---|
| Aucun fichier n'apparaît | `journalctl -u enregistrement-auto -f` (voir les erreurs) |
| "curl: (7) Failed to connect" | Le boîtier n'a pas internet — vérifie le câble Ethernet |
| ffmpeg s'arrête sans arrêt | Caméra injoignable — vérifie l'URL RTSP dans l'app |
| Disque plein | Augmente la purge : `RETENTION_DAYS=15` (ou disque plus grand) |
