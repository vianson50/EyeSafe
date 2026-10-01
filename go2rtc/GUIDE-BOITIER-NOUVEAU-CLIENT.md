# ═══════════════════════════════════════════════════════════
# GUIDE ULTRA-SIMPLE — Installer le boîtier d'enregistrement
# chez un nouveau client
# ═══════════════════════════════════════════════════════════

## 📋 Ce qu'il te faut avant de commencer

| Matériel | Où l'acheter | Prix approx. |
|---|---|---|
| Boîtier mini PC (Beelink S12 Mini) | Jumia / AliExpress | 45 000 FCFA |
| Disque dur externe USB (WD Purple 2 To) | Boutique informatique | 35 000 FCFA |
| Câble Ethernet (RJ45) | Boutique informatique | 2 000 FCFA |
| **Écran + clavier** (juste pour l'installation) | Tu en as déjà | — |
| **Ton ordinateur portable** | Tu en as déjà | — |

---

## 🔌 ÉTAPE 1 — Brancher le boîtier physiquement (5 min)

```
   Routeur du client
        │
        │ (câble Ethernet — relie le boîtier au routeur)
        │
   ┌────┴─────┐     ┌──────────────┐
   │  Boîtier │─────│ Disque dur   │
   │  (miniPC)│ USB │ (USB 3.0)    │
   └────┬─────┘     └──────────────┘
        │
   ┌────┴─────┐
   │ Écran +  │  (juste pour l'installation,
   │ clavier  │   tu l'enlèves après)
   └──────────┘
```

1. Branche le **câble Ethernet** du boîtier au **routeur du client**
2. Branche le **disque dur USB** sur le boîtier
3. Branche un **écran (câble HDMI)** et un **clavier USB** sur le boîtier
4. Branche l'**alimentation** → le boîtier démarre

---

## 🖥️ ÉTAPE 2 — Première ouverture du boîtier (10 min)

Quand le boîtier démarre pour la première fois :

### 2a. Installe le système (Debian/Ubuntu)

Si le boîtier est **vide** (pas de système) :
1. Télécharge [Debian 12](https://www.debian.org/download) ou [Ubuntu Server](https://ubuntu.com/download/server) sur une clé USB
2. Branche la clé USB sur le boîtier
3. Démarre → suis l'installation à l'écran
4. Quand il demande un **nom d'utilisateur** → tape `eyesafe`
5. Quand il demande un **mot de passe** → tape un mot de passe simple (note-le !)

> 💡 **Alternative** : certains boîtiers (Beelink) viennent avec Windows préinstallé.
> Pour ce guide, on préfère Linux (Debian/Ubuntu). Si ton boîtier a Windows,
> dis-moi et je te fais un guide Windows.

### 2b. Trouve l'adresse IP du boîtier

Sur l'écran branché au boîtier, tape :

```
ip addr show
```

Cherche la ligne qui ressemble à ça :
```
inet 192.168.1.150/24
```

**Note cette adresse** (ex: `192.168.1.150`) — c'est l'IP de ton boîtier.

> 💡 **Autre méthode** : regarde dans l'interface du routeur du client
> (http://192.168.1.1) → liste des appareils connectés → trouve le boîtier.

---

## 📱 ÉTAPE 3 — Se connecter au boîtier depuis TON ordinateur (5 min)

Maintenant tu vas **contrôler le boîtier depuis ton PC portable** (plus confortable que l'écran branché).

### Sur ton PC (Linux/Mac) :

Ouvre un **terminal** et tape :

```
ssh eyesafe@192.168.1.150
```

*(Remplace `192.168.1.150` par l'IP que tu as notée à l'étape 2b)*

- Il demande un mot de passe → tape celui que tu as choisi à l'étape 2a
- Si ça marche, tu vois : `eyesafe@boitier:~$`

**✅ Tu es maintenant DANS le boîtier, depuis ton PC !**

### Sur ton PC (Windows) :

Télécharge et installe [PuTTY](https://www.putty.org/) :
1. Ouvre PuTTY
2. Dans "Host Name" → tape `eyesafe@192.168.1.150`
3. Clique "Open"
4. Tape le mot de passe

---

## 📦 ÉTAPE 4 — Copier les fichiers vers le boîtier (5 min)

Les fichiers `enregistrement-auto.sh` et `enregistrement-auto.service` sont dans **ton projet** sur ton PC. Il faut les envoyer vers le boîtier.

### Sur ton PC (dans le projet eyesafe), ouvrez un NOUVEAU terminal et tape :

```
scp go2rtc/enregistrement-auto.sh go2rtc/enregistrement-auto.service eyesafe@192.168.1.150:/tmp/
```

*(Encore : remplace l'IP par celle de ton boîtier)*

- Il demande le mot de passe → tape-le
- Les fichiers sont maintenant sur le boîtier dans `/tmp/`

---

## ⚙️ ÉTAPE 5 — Configurer le boîtier (10 min)

Maintenant, retourne dans le terminal **SSH** (celui où tu es connecté au boîtier) et tape les commandes **une par une** :

### 5a. Installe les outils nécessaires

```
sudo apt update
```
*(demande ton mot de passe)*

```
sudo apt install -y ffmpeg curl python3
```
*(ça prend 2-3 minutes — attends)*

### 5b. Prépare le disque dur

⚠️ **ATTENTION** : cette étape EFFACE le disque dur. Assure-toi qu'il est vide ou que tu n'as rien dessus.

Trouve le nom de ton disque :
```
lsblk
```

Tu verras quelque chose comme :
```
NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda      8:0    0 456.1G  0 disk
├─sda1   8:1    0   512M  0 part /boot/efi
└─sda2   8:2    0 455.5G  0 part /
sdb      8:16   0   1.8T  0 disk              ← C'EST ÇA TON DISQUE (sdb)
└─sdb1   8:17   0   1.8T  0 part
```

Le **disque externe** est celui qui fait ~1.8T (2 To) — souvent `sdb` ou `sdc`.

**Formate le disque** (remplace `sdb1` par ce que tu as trouvé) :
```
sudo mkfs.ext4 /dev/sdb1
```
*(tape `y` si il demande confirmation)*

**Crée le dossier et monte le disque** :
```
sudo mkdir -p /mnt/recordings
sudo mount /dev/sdb1 /mnt/recordings
```

**Fais en sorte que le disque se monte tout seul au démarrage** :
```
echo '/dev/sdb1 /mnt/recordings ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab
```

**Vérifie que ça marche** :
```
df -h /mnt/recordings
```
→ Doit afficher ~1.8T disponible ✅

### 5c. Installe le script d'enregistrement

```
sudo mkdir -p /opt/go2rtc
sudo cp /tmp/enregistrement-auto.sh /opt/go2rtc/
sudo cp /tmp/enregistrement-auto.service /etc/systemd/system/
sudo chmod +x /opt/go2rtc/enregistrement-auto.sh
```

### 5d. ⚠️ LE SEUL truc à changer : le SITE_ID

Ouvre le script pour le modifier :
```
sudo nano /opt/go2rtc/enregistrement-auto.sh
```

Avec les **flèches du clavier**, descends jusqu'à la ligne 24 environ :
```
SITE_ID="2711ccb8-d629-442b-b884-a6be8e40cc2c"
```

**Change cette valeur** par l'UUID du site de ton nouveau client.

> **Comment trouver l'UUID ?** Sur TON PC (pas le boîtier), dans le projet :
> ```
> curl -s -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtaGZ0aWFmdmJvZWx5Z3N1bmR6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk0NzQ0MjAsImV4cCI6MjEwNTA1MDQyMH0._s9P6tJrv2DiSQdGp6rYH3rN7sc8--Twt1-qllvYjVU" \
>   "https://rmhftiafvboelygsundz.supabase.co/rest/v1/sites?select=id,name" \
>   | python3 -m json.tool
> ```
> → Copie le `id` du site du client.

Une fois modifié :
- `Ctrl + O` (sauvegarder)
- `Entrée` (confirmer)
- `Ctrl + X` (quitter)

### 5e. Démarre le service

```
sudo systemctl daemon-reload
sudo systemctl enable --now enregistrement-auto
```

### 5f. Vérifie que ça marche !

```
sudo journalctl -u enregistrement-auto -f
```

Tu dois voir apparaître :
```
[2026-10-01 14:30:00] [enregistrement-auto] Démarrage — site ...
[2026-10-01 14:30:00] [enregistrement-auto] Caméras actives : 8
[2026-10-01 14:30:00] [enregistrement-auto] ▶ DÉMARRAGE : Caméra 1
[2026-10-01 14:30:00] [enregistrement-auto] ▶ DÉMARRAGE : Caméra 2
...
```

**Appuie sur `Ctrl + C` pour arrêter de regarder les logs.**

Vérifie que les fichiers apparaissent sur le disque :
```
ls /mnt/recordings/
```
→ Tu dois voir : `Caméra 1/`, `Caméra 2/`, etc.

---

## ✅ ÉTAPE 6 — C'est fini !

Tu peux maintenant :
1. **Débrancher l'écran et le clavier** du boîtier
2. Poser le boîtier quelque part de discret (étagère, derrière le routeur)
3. Il tourne tout seul, 24/7, sans que personne n'y touche

---

## 🔄 Pour un DEUXIÈME client (la prochaine fois)

1. Achète un autre boîtier + disque dur
2. Fais **exactement les mêmes étapes** (1 à 6)
3. La seule différence : change le `SITE_ID` (étape 5d) par l'UUID du 2e site
4. Fini !

---

## 🩺 Si ça ne marche pas

| Problème | Solution |
|---|---|
| Je ne peux pas me connecter en SSH | Vérifie que le boîtier et ton PC sont sur le **même réseau** (même WiFi/routeur) |
| "curl: (7) Failed to connect" | Le boîtier n'a pas internet — vérifie le câble Ethernet au routeur |
| Aucun fichier n'apparaît | Tape `sudo journalctl -u enregistrement-auto -n 50` et envoie-moi le résultat |
| "ffmpeg: Connection refused" | La caméra est injoignable — vérifie que le direct marche dans l'app |
| Le disque ne monte pas au boot | Vérifie l'étape 5b (fstab) et le câble USB |

---

## 📱 Résumé en image

```
TON PC                    BOÎTIER CHEZ LE CLIENT
──────                    ───────────────────────
                          [écran + clavier branchés
                           juste pour installer]
    │
    │ (WiFi du client)
    │
    └── ssh eyesafe@IP ──► [terminal du boîtier]
    │                        │
    ├── scp fichiers ─────► [fichiers copiés]
    │                        │
    │                        ├── apt install ffmpeg
    │                        ├── monter disque
    │                        ├── systemctl start
    │                        │
    │                        ▼
    │                    📼 ENREGISTRE TOUS SEUL
    │
    └── Dans l'APP : les caméras connectées
        → le boîtier les détecte → enregistre
```
