# ═══════════════════════════════════════════════════════════
# GUIDE COMPLET — Enregistrements chez un nouveau client
#
# 3 situations possibles — choisis celle de ton client :
#
#  ┌─────────────────────────────────────────────────────┐
#  │  SITUATION A : Le client a un NVR/DVR → RIEN À FAIRE │
#  │  SITUATION B : Caméras IP seules → boîtier + disque  │
#  │  SITUATION C : VPS OVH pour le direct à distance       │
#  └─────────────────────────────────────────────────────┘
# ═══════════════════════════════════════════════════════════

---

## 🎯 D'ABORD — Identifier la situation (30 secondes)

Demande-toi :

**« Est-ce que le client a une boîte qui enregistre déjà ? »**

| Ce que le client a | Situation | Guide |
|---|---|---|
| Un **NVR** (Network Video Recorder — boîte avec disque dur, toutes les caméras branchées dessus) | **A** | ↓ Section A |
| Un **DVR** (Digital Video Recorder — caméras analogiques coaxiales branchées dessus) | **A** | ↓ Section A |
| Un **NVR hybride** (accepte IP + coaxial) | **A** | ↓ Section A |
| Des **caméras IP Wi-Fi/Ethernet** sans boîte d'enregistrement | **B** | ↓ Section B |
| Des **caméras Wi-Fi grand public** (Tapo, Ezviz, Xiaomi…) | **B** (limité) | ↓ Section B |
| Rien encore — tu installes tout | **Ton choix** | A ou B |

> 💡 **Comment reconnaître un NVR/DVR** : c'est une boîte noire avec
> des prises pour les caméras à l'arrière, un disque dur à l'intérieur,
> souvent la marque Hikvision ou Dahua. Elle est branchée à un écran
> ou au routeur.

---

# ═══════════════════════════════════════════════════════════
# SECTION A — Le client a un NVR/DVR (le PLUS SIMPLE)
# ═══════════════════════════════════════════════════════════

## ✅ Bonne nouvelle : RIEN à installer !

Le NVR/DVR **enregistre déjà** sur son propre disque dur. L'app
EyeSafe lit les enregistrements via **ONVIF Replay** (bouton 🕘).

```
NVR/DVR du client (ex: Dahua, Hikvision)
    │
    ├── Enregistre sur SON disque dur interne ✅
    ├── Fournit le flux RTSP à l'app ✅
    └── L'app lit le replay via ONVIF (bouton 🕘) ✅
```

## 📋 Ce que tu vérifies (5 minutes)

### A1. Le NVR a un disque dur

**Dans l'interface du NVR** (écran branché ou navigateur web) :

| Marque | Où regarder |
|---|---|
| **Dahua** | Main Menu → Info → HDD/Hard Disk |
| **Hikvision** | Configuration → Storage → Storage Management |
| **Autre** | Cherche "Disque dur" ou "HDD" ou "Storage" |

→ Doit afficher un disque avec de l'espace libre.
→ Si **pas de disque** : achètes-en un (WD Purple 2 To ~35 000 FCFA)
   et installes-le dans le NVR (souvent une simple vis + glisser).

### A2. L'enregistrement est activé

**Dans l'interface du NVR** :

| Marque | Où |
|---|---|
| **Dahua** | Main Menu → Manage → Record Config → cocher toutes les caméras |
| **Hikvision** | Configuration → Record → Schedule → cocher "Continuous" pour toutes |
| **Autre** | Cherche "Recording Schedule" ou "Record Plan" |

→ Mode : **Continu** (24/7) ou **Mouvement** (seulement les événements)
→ **Toutes les caméras** doivent être cochées

### A3. La rétention (combien de jours)

**Dans l'interface du NVR** :
- Cherche "Rétention" ou "Overwrite" ou "Recycle"
- Mets **30 jours** (ou selon la taille du disque)

> 📊 **Règle approximative** : 2 To ≈ 30 jours pour 8 caméras
> en sous-flux (qualité normale). Pour le flux principal (HD),
> compte 2 To ≈ 7-10 jours pour 8 caméras.

### A4. Branche le NVR au routeur (si pas déjà fait)

- Câble Ethernet du NVR → routeur du client
- Le NVR obtient une IP automatiquement (DHCP)
- **Note l'IP** (affichée dans le NVR : Info → Network → TCP/IP)

## 📱 Connecter les caméras dans l'app (2 minutes)

1. Ouvre l'app en tant que **technicien**
2. Va sur le site du client (sélecteur en haut)
3. **Caméras → Connecter un NVR**
4. Choisis **NVR LOCAL**
5. Entre :
   - IP du NVR (ex: `192.168.100.72`)
   - Port : `554` (ou `80` si le NVR l'exige)
   - Utilisateur + mot de passe du NVR
   - Nombre de canaux (ex: 8)
6. **Créer les caméras** → elles apparaissent ✅

## 🕘 Revoir les enregistrements (déjà implémenté !)

1. Tape une caméra → le direct s'ouvre
2. Tape le bouton **🕘** (en haut à droite)
3. Choisis un jour → les segments apparaissent
4. Tape un segment → il se rejoue ✅

> 💡 Si le bouton 🕘 ne montre rien : vérifie A1 (disque) et
> A2 (enregistrement activé) dans le NVR.

## 💰 Coût pour le client

| Ce qu'il a déjà | Ce qu'il manque | Coût |
|---|---|---|
| NVR + disque + caméras | Rien | **0 FCFA** ✅ |
| NVR sans disque | Disque WD Purple 2 To | 35 000 FCFA |
| Ni NVR ni caméras | NVR complet (Dahua 8ch + disque) | ~150 000 FCFA |

---

# ═══════════════════════════════════════════════════════════
# SECTION B — Caméras IP seules (sans NVR) → boîtier
# ═══════════════════════════════════════════════════════════

## 📋 Ce qu'il te faut

| Matériel | Prix approx. |
|---|---|
| Boîtier mini PC (Beelink S12 Mini / Android TV Box) | 10-45 000 FCFA |
| Disque dur externe USB 3.0 (WD Purple 2 To) | 35 000 FCFA |
| Câble Ethernet | 2 000 FCFA |
| Écran + clavier (pour l'installation seulement) | — |

---

## 🔌 ÉTAPE B1 — Brancher le boîtier physiquement (5 min)

```
   Routeur du client
        │
        │ (câble Ethernet)
        │
   ┌────┴─────┐     ┌──────────────┐
   │  Boîtier │─────│ Disque dur   │
   │  (miniPC)│ USB │ externe USB  │
   └────┬─────┘     └──────────────┘
        │
   ┌────┴─────┐
   │ Écran +  │  (juste pour installer,
   │ clavier  │   tu débranches après)
   └──────────┘
```

1. Branche le **câble Ethernet** du boîtier au **routeur**
2. Branche le **disque dur USB** sur le boîtier
3. Branche un **écran (HDMI)** et un **clavier USB**
4. Branche l'**alimentation** → le boîtier démarre

---

## 🖥️ ÉTAPE B2 — Premier démarrage du boîtier (10 min)

### B2a. Installe le système (si le boîtier est vide)

1. Télécharge [Ubuntu Server](https://ubuntu.com/download/server) sur une clé USB
2. Branche la clé sur le boîtier → démarre
3. Suis l'installation à l'écran
4. Nom d'utilisateur : `eyesafe` / mot de passe : quelque chose de simple

### B2b. Trouve l'adresse IP du boîtier

Sur l'écran branché au boîtier, tape :
```
ip addr show
```
Cherche `inet 192.168.1.XXX` → **note cette IP**

---

## 📱 ÉTAPE B3 — Se connecter au boîtier depuis TON PC (5 min)

Sur **ton PC portable** (connecté au même WiFi que le boîtier) :

```
ssh eyesafe@192.168.1.XXX
```
→ Tape le mot de passe → tu es dans le boîtier ✅

> 💡 **Sur Windows** : télécharge [PuTTY](https://www.putty.org/)
> et mets l'IP dans "Host Name"

---

## 📦 ÉTAPE B4 — Envoyer les fichiers vers le boîtier (2 min)

Sur **ton PC** (dans le projet eyesafe), dans un NOUVEAU terminal :

```
scp go2rtc/enregistrement-auto.sh go2rtc/enregistrement-auto.service eyesafe@192.168.1.XXX:/tmp/
```

---

## ⚙️ ÉTAPE B5 — Configurer le boîtier (10 min, une seule fois)

Dans le terminal **SSH** (connecté au boîtier), tape chaque commande :

### B5a. Installe les outils
```
sudo apt update
sudo apt install -y ffmpeg curl python3
```

### B5b. Prépare le disque dur

⚠️ Ça **efface** le disque — assure-toi qu'il est vide !

```
lsblk
```
→ Trouve ton disque externe (celui qui fait ~1.8T, souvent `sdb`)

```
sudo mkfs.ext4 /dev/sdb1
sudo mkdir -p /mnt/recordings
sudo mount /dev/sdb1 /mnt/recordings
echo '/dev/sdb1 /mnt/recordings ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab
df -h /mnt/recordings
```
→ Doit afficher ~1.8T ✅

### B5c. Installe le script
```
sudo mkdir -p /opt/go2rtc
sudo cp /tmp/enregistrement-auto.sh /opt/go2rtc/
sudo cp /tmp/enregistrement-auto.service /etc/systemd/system/
sudo chmod +x /opt/go2rtc/enregistrement-auto.sh
```

### B5d. ⚠️ Change le SITE_ID (le SEUL truc à modifier)

```
sudo nano /opt/go2rtc/enregistrement-auto.sh
```
Descends à la ligne ~24 :
```
SITE_ID="2711ccb8-d629-442b-b884-a6be8e40cc2c"
```
→ Remplace par l'UUID du site de **ce client**

**Pour trouver l'UUID** (sur ton PC) :
```
curl -s -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtaGZ0aWFmdmJvZWx5Z3N1bmR6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk0NzQ0MjAsImV4cCI6MjEwNTA1MDQyMH0._s9P6tJrv2DiSQdGp6rYH3rN7sc8--Twt1-qllvYjVU" "https://rmhftiafvboelygsundz.supabase.co/rest/v1/sites?select=id,name" | python3 -m json.tool
```

Sauvegarde : `Ctrl+O` → `Entrée` → `Ctrl+X`

### B5e. Démarre le service
```
sudo systemctl daemon-reload
sudo systemctl enable --now enregistrement-auto
```

### B5f. Vérifie
```
sudo journalctl -u enregistrement-auto -f
```
→ Doit afficher `▶ DÉMARRAGE : Caméra 1...` pour chaque caméra ✅

```
ls /mnt/recordings/
```
→ Tu dois voir les dossiers `Caméra 1/`, `Caméra 2/`, etc.

---

## ✅ ÉTAPE B6 — C'est fini !

1. **Débranche l'écran et le clavier**
2. Pose le boîtier quelque part de discret
3. Il tourne 24/7 tout seul

---

# ═══════════════════════════════════════════════════════════
# SECTION C — VPS OVH (pour le direct < 1 s à distance)
# ═══════════════════════════════════════════════════════════

> ⚠️ Le VPS est **optionnel** — il améliore la vitesse du direct
> à distance mais n'est pas obligatoire pour enregistrer.

## Ce que le VPS apporte

| Sans VPS | Avec VPS OVH |
|---|---|
| Direct à distance : lent (RTSP direct) | Direct à distance : **< 1 seconde** (WebRTC) |
| Accès distant : redirection de port sur le routeur | **Aucun port ouvert** (tunnel sortant) |
| Aperçus mosaïque : non (RTSP direct) | Aperçus mosaïque : **oui** (WebRTC) |

## Pour l'installer

Vois le guide détaillé : **`GUIDE-OVH.md`** dans ce même dossier.

---

# ═══════════════════════════════════════════════════════════
# 📊 TABLEAU RÉCAPITULATIF — Quelle situation, quelle action ?
# ═══════════════════════════════════════════════════════════

| Situation client | Matériel à acheter | Installation | Enregistrement |
|---|---|---|---|
| **A : NVR/DVR avec disque** | Rien | 5 min (vérifs NVR) | NVR enregistre ✅ |
| **A : NVR sans disque** | Disque 2 To (35 000 F) | 10 min (installer le disque) | NVR enregistre ✅ |
| **B : Caméras IP seules** | Boîtier + disque (80 000 F) | 35 min (guide Section B) | Boîtier enregistre ✅ |
| **B : Caméras Wi-Fi (Tapo…)** | Boîtier + disque (80 000 F) | 35 min + activer RTSP | Boîtier enregistre ✅ |
| **C : + VPS OVH** | VPS (4 000 F/mois) | 30 min (GUIDE-OVH.md) | N'importe laquelle |

---

# ═══════════════════════════════════════════════════════════
# 🩺 DÉPANNAGE GÉNÉRAL
# ═══════════════════════════════════════════════════════════

## Section A (NVR/DVR)

| Problème | Solution |
|---|---|
| Le bouton 🕘 ne montre rien | Vérifie le disque + l'enregistrement dans le NVR (A1, A2) |
| Le direct ne marche pas | Vérifie le câble Ethernet NVR-routeur + l'IP |
| Le replay montre des trous | L'enregistrement était coupé — vérifie le planning |

## Section B (Boîtier)

| Problème | Solution |
|---|---|
| SSH ne marche pas | Ton PC et le boîtier doivent être sur le **même réseau** |
| Aucun fichier sur le disque | `sudo journalctl -u enregistrement-auto -n 50` et envoie-moi le résultat |
| ffmpeg s'arrête sans arrêt | Caméra injoignable — vérifie l'URL RTSP dans l'app |
| Disque plein | Réduis `RETENTION_DAYS=15` ou achètes un plus gros disque |
