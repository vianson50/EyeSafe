# EYESAFE — Espace client vidéosurveillance

Application Flutter multi-plateformes (Android / iOS) pour une société
d'installation de vidéosurveillance : le **client** suit son installation
(caméras en direct, équipements, tickets, maintenance), le **technicien**
connecte les caméras et répond aux incidents.

- **2 rôles** : `client` (propriétaire de ses installations, inscription
  autonome) et `technicien` (**équipe globale** — voit tous les sites,
  migration 9) — gérés côté Supabase (table `profiles`).
- **Mode réel uniquement** : l'app exige un backend Supabase configuré
  (dart-defines) — un APK compilé sans configuration affiche un écran
  d'erreur explicite au lieu d'un mode démo.
- **Identité production** : `ci.eyesafe.app`, signée avec un keystore
  dédié (`~/eyesafe-release.keystore`, hors du projet — **à sauvegarder**).

---

## 1. Démarrage rapide

### Mode production (backend Supabase) — le seul mode

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

Les identifiants du projet sont dans `supabase_defines.json`.
Le premier écran est la **page de connexion** :
- **Client** : s'inscrit seul (« Créer un compte ») → crée son installation
  (« Créez votre installation ») → autonome de bout en bout.
- **Technicien** : créé par l'administrateur (`supabase/create_users.sh`),
  voit **toutes** les installations de tous les clients.
- **Mots de passe** : changement dans l'app (Paramètres → Compte) et
  réinitialisation par email (« Mot de passe oublié ? ») — aucun besoin
  d'administrateur.

### Compiler l'APK

```bash
./build_apk.sh          # APK complet (~133 Mo, toutes architectures)
./build_apk.sh --split  # un APK par ABI (~47 Mo pour arm64)
```

> ⚠️ **Toujours utiliser `./build_apk.sh`**, jamais `flutter build apk` nu :
> sans les dart-defines, l'APK affiche l'écran « configuration serveur
> manquante » (le mode démo a été retiré).

Installation : `adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

### Tests et analyse

```bash
flutter analyze   # 0 problème attendu
flutter test      # 130 tests (unitaires + widgets)
```

---

## 2. Structure du projet

```
lib/
├── main.dart                  # Point d'entrée (MediaKit, backend, push)
├── core/
│   ├── app_config.dart        # dart-defines (SUPABASE_URL / ANON_KEY)
│   ├── backend.dart           # init Supabase
│   └── push_service.dart      # FCM + notifications locales
├── data/
│   ├── models.dart            # Equipment, Ticket, MaintenanceVisit…
│   ├── demo_data.dart         # Données locales des TESTS (jamais en prod)
│   ├── site_controller.dart   # Contrôleur central (CRUD + temps réel
│   │                          #   + autorisations serveur flux/PTZ)
│   ├── onvif.dart             # ONVIF : WS-Discovery, profils, PTZ,
│   │                          #   filtre IR (Imaging), événements PullPoint,
│   │                          #   replay (Recording Search), Digest SHA-1
│   ├── isapi.dart             # Hikvision ISAPI (Digest MD5, deviceInfo,
│   │                          #   canaux, motion, PTZ caps)
│   ├── brand_api.dart        # Axis VAPIX + Uniview LAPI (Digest MD5)
│   ├── dahua_api.dart         # Dahua HTTP API (login signé 2 temps)
│   ├── http_digest.dart       # Auth Digest MD5 partagée (3 adaptateurs)
│   ├── go2rtc.dart            # Relais go2rtc + snapshots + appairage cloud
│   ├── g711.dart              # Codec G.711 μ-law/A-law (talk-back)
│   ├── whep.dart              # Négociation WebRTC/WHEP (latence < 1 s)
│   ├── rtc_config.dart        # STUN/TURN configurables (perçage NAT)
│   ├── theme_settings.dart    # Thème clair/sombre (suit le système)
│   └── stream_scheduler.dart  # Bande passante mosaïque (quota live,
│                              #   snapshots 5 s, dégradation auto)
├── pages/
│   ├── dashboard_page.dart    # Tableau de bord
│   ├── cameras_page.dart      # Mosaïque + 7 modes de connexion + direct
│   │                          #   (WebRTC/HLS/RTSP, PTZ, IR, aperçus)
│   ├── equipment_page.dart    # Inventaire équipements
│   ├── support_page.dart      # Tickets + alertes
│   ├── settings_page.dart     # Paramètres (réseau, notifs, compte, mots de passe)
│   ├── maintenance_page.dart  # Visites, rapports, contrat
│   └── login_page.dart        # Connexion / inscription
└── ui/
    ├── app_shell.dart         # Shell (sidebar/header/drawer + menu compte)
    ├── auth_gate.dart         # Routeur session → AppShell | LoginPage
    ├── data_scope.dart        # InheritedNotifier → SiteController
    ├── notifications_panel.dart
    ├── splash_screen.dart
    ├── theme.dart             # Couleurs, polices (Jakarta/Mono)
    └── widgets/common.dart    # PageHeader, PrimaryButton, WhiteCard…

go2rtc/                        # Serveur vidéo relais (config + scripts)
supabase/                      # Migrations SQL, seed, scripts Python
build_apk.sh                   # Build APK avec backend configuré
test/                          # 130 tests (protocoles, UI, sécurité, thème, événements)
```

---

## 3. Rôles et fonctionnalités

| Fonctionnalité | Client | Technicien |
|---|---|---|
| Tableau de bord (état système, stats, alertes) | ✅ | ✅ |
| Caméras en direct (WebRTC < 1 s, HLS/RTSP repli) | ✅ | ✅ |
| Aperçus mosaïque (quota live + snapshots 5 s) | ✅ | ✅ |
| Pavé PTZ (caméras motorisées, autorisé serveur) | ✅ | ✅ |
| Filtre IR jour/nuit/auto (ONVIF Imaging) | ✅ | ✅ |
| Replay des enregistrements (ONVIF standard + repli ISAPI) | ✅ | ✅ |
| Talk-back : parler dans la caméra (maintenir 🎙) | ✅ | ✅ |
| Badge « MOUVEMENT » temps réel (événements ONVIF) | ✅ | ✅ |
| Déconnexion caméra / équipement | ✅ | ✅ |
| **Connecter des caméras** (7 méthodes, cf. §4) | ❌ | ✅ |
| **Réglages réseau** ⚙ (quota live, STUN/TURN) | ❌ | ✅ |
| Répondre aux tickets (dépannage planifié) | ❌ | ✅ |
| Signaler un incident | ✅ | ✅ |
| Tous les sites (équipe, migration 9) | ❌ | ✅ |
| Multi-sites (changement de site) | ✅ | ✅ |
| Création de compte + installation autonome | ✅ | ❌ (créé par l'admin) |
| Changer mon mot de passe / oublié | ✅ | ✅ |
| Déconnexion du compte (menu 👤 en haut à droite) | ✅ | ✅ |

Le rôle est lu depuis `profiles.role` côté serveur (jamais depuis les
métadonnées utilisateur modifiables).

**Partage de téléphone** : le client se déconnecte (👤 → Se déconnecter) →
retour à l'écran de connexion → le technicien connecte son compte.

---

## 4. Les 7 méthodes de connexion des caméras

Le dialogue « Connecter les caméras » (technicien uniquement) propose :

| # | Onglet | Usage | Portée |
|---|---|---|---|
| 1 | **NVR LOCAL** | NVR Hikvision/Dahua/Axis/Uniview/Imou sur le WiFi du site — crée 1 caméra par canal | LAN |
| 2 | **IP / DOMAINE** | IP publique ou DynDNS + port public redirigé → 554 (comme iDMSS/tinyCam), avec test TCP | Distant |
| 3 | **ONVIF** | Découverte WS-Discovery automatique, profils main/sub, PTZ, filtre IR jour/nuit — toutes marques | LAN |
| 4 | **RELAI GO2RTC** | Le serveur go2rtc du site tire le RTSP et rediffuse en HLS — 1 seule adresse | Distant |
| 5 | **CLOUD (P2P)** | Appairage par code boîtier (`EYE-7F3K2`) sur TON cloud go2rtc — zéro config client | Distant |
| 6 | **API MARQUE** | SDK HTTP propriétaire : ISAPI (Hikvision), HTTP API (Dahua), VAPIX (Axis), LAPI (Uniview) — deviceInfo réel, détection de mouvement | LAN |
| 7 | **URL SIMPLE** | URL de flux exacte (rtsp://…, http://…m3u8) | — |

### Chemins RTSP par marque (`SiteController.rtspUrlFor`)

| Marque | Chemin (flux secondaire) |
|---|---|
| Hikvision | `/Streaming/Channels/{ch}02` |
| Dahua | `/cam/realmonitor?channel={ch}&subtype=1` |
| Imou (= Dahua) | `/cam/realmonitor?channel={ch}&subtype=1` |
| Axis | `/axis-media/media.amp?camera={ch}&videocodec=h264&resolution=640x360&fps=15` |
| Uniview | `/unicast/c{ch}/s1/live` |

### SDK propriétaires — un adaptateur par marque

Intégrer un SDK ne sert qu'à SA marque : l'ISAPI Hikvision ne contrôle
pas une Dahua. L'app code donc un **adaptateur par constructeur**, tous
en Dart pur sur le même patron (auth + parsing testables) :

| Marque | Voie intégrée | Voie native non intégrée |
|---|---|---|
| Hikvision | **ISAPI** (HTTP REST, recommandée) — deviceInfo, canaux, motion, PTZ, HTTP Digest MD5 | HCNetSDK (.so/AAR sous licence) |
| Dahua | **HTTP API** (JSON-RPC `/cgi-bin/…`) — login signé MD5 deux temps + session, `magicBox.getSystemInfo` | NetSDK (.so) |
| Axis | **VAPIX** (`param.cgi`) — deviceInfo, Digest MD5 | ACAP (apps embarquées caméra) |
| Uniview | **LAPI** (`/LAPI/V1.0/…`, JSON) — deviceInfo | SDK Uniview |
| Imou | RTSP/ONVIF uniquement (cloud fabricant, pas d'API locale) | Imou Life (cloud) |

Pourquoi les HTTP API plutôt que les SDK natifs : zéro binaire sous
licence, zéro bridge plateforme, code testable — et ce sont les voies que
les constructeurs recommandent pour les nouvelles intégrations.

Rôles respectifs ONVIF vs API marque : ONVIF couvre le socle universel
(découverte, flux, PTZ, IR) ; l'API marque ajoute la configuration
profonde (motion/intrusion, et à terme lecture/playback, événements
d'alarme, mise à jour distante) et l'analytique propriétaire.

### Le socle universel ONVIF — et sa limite

ONVIF est le seul « langage commun » mondial : découverte (WS-Discovery),
authentification (UsernameToken Digest), flux (GetStreamUri → RTSP
H.264), contrôles de base (PTZ continu, **filtre IR jour/nuit** via le
service Imaging, …). Tout est câblé dans `lib/data/onvif.dart`.

**Limite fondamentale** : ONVIF standardise *le transport*, pas *le
contenu*. Les métadonnées analytiques (reconnaissance personnes/véhicules,
cadres de délimitation, scores de confiance) ne sont **pas uniformes** :
certaines caméras ne remontent qu'un événement « mouvement », d'autres des
bounding boxes complètes, d'autres encore n'exposent ces données que via
leurs interfaces propriétaires. Pour l'analytique profonde → mode
**API MARQUE** (ISAPI/VAPIX/LAPI).

### P2P / Relais à grande échelle

Le modèle P2P : appareil et app s'authentient d'abord auprès du cloud,
puis tentent le direct par **hole punching UDP** (STUN) ; si le NAT
refuse, le flux est **relié par le serveur** (TURN ou HLS cloud).

Où en est EyeSafe sur ce modèle :

- **Signaling + direct** : le WebRTC (WHEP) est prioritaire partout —
  transport UDP point-à-point, latence < 1 s.
- **Hole punching** : STUN configuré (défaut Google) ; **TURN
  optionnel** (⚙ → Réglages réseau, ex: coturn) pour survivre aux NAT
  symétriques SANS retomber sur le HLS relayé.
- **Relais serveur** : repli HLS via le cloud go2rtc — toujours
  fonctionnel, plus coûteux en bande passante serveur.
- **Sur site** : les caméras branchées en RELAI GO2RTC streament
  directement depuis le boîtier du site (zéro bande passante cloud).

Non intégrés (décision assumée, comme HCNetSDK/NetSDK) :

- **TUTK** (ThroughTek) : SDK P2P tiers le plus répandu du marché IPC —
  natif, sous licence, binaire fermé. L'architecture go2rtc + WebRTC
  couvre le même cas d'usage sans dépendance commerciale.
- **ONVIF Profile V** (VSaaS, encore en Release Candidate) : impose aux
  appareils des connexions sortantes WSS + flux WebRTC basse latence —
  exactement la direction de notre stack ; à adopter quand les
  firmwares le déployeront.

### Replay & talk-back (le direct ne suffit pas)

Un service de surveillance sans **replay** est inutilisable ; le
**talk-back** est un standard du marché.

- **Replay — ONVIF standard en priorité** (Recording Search
  `ver10/search.wsdl`) : couvre **Dahua, Axis, Uniview, Hikvision**
  d'un coup — bouton 🕘, navigateur de segments par jour (heures,
  durées, badge « · ONVIF »), lecture RTSP via `GetReplayUri` dans le
  lecteur existant, badge `REPLAY HH:MM` + « RETOUR DIRECT ».
  Orchestration complète : FindRecordings → pagination → EndSearch,
  cap 20 segments. **Repli automatique ISAPI** (`ContentMgmt/search` +
  piste RTSP) pour les Hikvision sans le service standard.
- **Talk-back** — bouton 🎙 : **maintenir pour parler**. Le micro est
  capturé en PCM 16 bits 8 kHz mono (annulation d'écho + réduction de
  bruit), encodé **G.711 μ-law** puis streamé vers
  `/ISAPI/System/Audio/channels/1/talk-data` (session `openTalk` en
  Digest, flux chunked, `DELETE openTalk` à la relâche). Le bouton passe
  au vert pendant l'émission. (Hikvision uniquement — le talk-back
  n'est pas standardisé ONVIF.)

> Variance firmwares : les endpoints talk/search varient selon les
> générations — best-effort avec erreurs explicites ; valider sur chaque
> modèle déployé.

### Événements temps réel (alertes intrusion/mouvement)

Pipeline complet ONVIF PullPoint → anti-bruit → persistance :

- **CameraEventPoller** par caméra RTSP avec identifiants : pull 3 s,
  renouvellement à mi-vie, auto-réparation (re-souscription 30 s
  après échec) — intégré à `SiteController` (diff d'inventaire,
  arrêt au changement de site).
- **Anti-bruit** (une caméra émet ~50 évts/min sinon) : dédup
  30 s par (caméra, topic), priorisation (`isCritical` : tamper/
  intrusion/VideoLoss → alertes ; mouvement → historique), résumé
  « Activité multiple — N caméras ».
- **Badge « MOUVEMENT »** animé sur les tuiles (état dérivé du
  contrôleur central, fenêtre de grâce 34 s anti-clignotement).
- **Persistance** : les critiques uniquement → table `camera_events`
  (migration 10 : RLS tenant, index site+temps, Realtime, purge 7 j
  en conservant les preuves intrusion/tamper) — le mouvement reste en
  mémoire.
- **Parseur robuste** : `SimpleItem` (canonique) ET `SimpleItemValue`
  (variant firmware), items State/IsMotion/IsActive, valeurs
  true/yes/1, sujets hiérarchiques décomposés (`topicSegments`).

> Limite : le poller ne tourne que lorsqu'une app (technicien) est
> ouverte. Pour du 24/7 sans app → Edge Function worker (sujet distinct).

### Architecture recommandée (terrain)

1. **Sur site** : ONVIF (découverte) ou NVR LOCAL pour rattacher les caméras.
2. **Chez le client** : un boîtier go2rtc tire le RTSP en local.
3. **Accès distant** : le boîtier pousse vers TON cloud go2rtc (connexion
   sortante, aucun port ouvert) → le client ne configure rien (CLOUD P2P).

---

## 5. Backend Supabase

### Schéma (migrations dans `supabase/migrations/`)

- `profiles` — rôle (`client`/`technicien`/`admin`), nom, token FCM
- `sites` — installations (propriétaire via `owner_id`)
- `site_technicians` — historique d'assignation (optionnelle depuis la
  migration 9 : les techniciens ont un accès global, plus d'assignation
  requise pour intervenir)
- `equipment` — équipements + `stream_url`
- `tickets`, `maintenance_visits`, `alerts`, `notifications`
- `stream_audit` — journal des accès aux flux, avec colonne `action`
  (`stream` / `ptz`) — migrations 7 et 8
- `camera_events` — événements critiques persistés (intrusion, tamper…)
  avec RLS tenant, Realtime et purge 7 j — migration 10
- `camera_event_subscriptions` — état des souscriptions PullPoint
  (usage interne app) — migration 10

> 💡 La **migration 8 est auto-suffisante** : elle inclut la table et
> `get_stream_url` (migration 7) au cas où cette dernière n'aurait pas été
> appliquée. Tout est idempotent — ré-exécutable sans erreur, ordre libre.

### Sécurité multi-clients

- **RLS partout** : un client ne lit que ses sites ; un **technicien**
  accède à **tous** les sites (`can_access_site` = propriétaire OU
  technicien, migration 9).
- **`get_stream_url(equipment_id)`** (RPC security definer) : l'accès à un
  flux est **revérifié côté serveur à chaque requête** (tenant + rôle) —
  y compris les aperçus mosaïque (snapshots et WebRTC) — avec
  journalisation dans `stream_audit`.
- **`can_control_ptz(equipment_id)`** (migration 8) : le contrôle PTZ,
  action physique sensible, est autorisé séparément et journalisé
  (`action='ptz`) — pavé masqué si refusé.
- **Limites connues** : les URLs RTSP avec identifiants restent lisibles
  dans `equipment.stream_url` (nécessaire au direct IP). Quand tout passe
  par le relais, décommenter le `REVOKE` de la migration 7 pour verrouiller.

### Scripts utiles (`supabase/`)

```bash
supabase/create_users.sh       # créer comptes client/technicien (Admin API)
supabase/purge_demo_data.sql   # retirer les données de démo du backend
supabase/use_go2rtc_streams.py# brancher les flux sur go2rtc
```

### Emails (mots de passe)

Le « Mot de passe oublié » et les confirmations d'inscription utilisent le
**SMTP intégré de Supabase** — fonctionnel mais limité (2-3 emails/heure,
arrive souvent en spam). Quand le volume le justifiera : acheter un domaine
(~5 000 FCFA/an) et configurer Resend ou Brevo en Custom SMTP
(Authentication → Emails) — la marche à suivre est documentée dans
l'historique du projet.

### Comptes de production

Créés via `create_users.sh` — mots de passe dans `~/comptes_eyesafe.txt`
(hors du projet). Les utilisateurs changent leur mot de passe eux-mêmes
dans l'app (Paramètres → Compte) ou via « Mot de passe oublié ».

---

## 6. Robustesse UI (points traités)

- **Thème sombre** : suit le réglage du téléphone (`ThemeSettings`),
  palette adaptative complète (cartes, dialogs, snacks, sidebar), bascule
  instantanée sans mélange (ordre palette→rebuild, widgets non-const,
  thème déterministe).
- **Adaptatif** : en-têtes, grilles et cartes basculent en mode compact
  sous 700px — jamais de texte coupé verticalement, boutons sous le titre.
- **Capacités** : le pavé PTZ n'apparaît que si la caméra le déclare
  (ONVIF `PTZConfiguration` ou ISAPI `PTZCapability`) ; le bouton IR
  n'apparaît que si le service Imaging répond ; l'audio est détecté
  (marqueur `· AUDIO`) — les boutons inutiles sont masqués.
- **Mode offline** : chaque tuile sonde son hôte (TCP) → badge
  « HORS LIGNE » ; l'écran d'erreur du lecteur propose « Réessayer » ;
  un aperçu WebRTC qui échoue bascule en snapshot sans planter.
- **Autorisation serveur** : chaque direct ET chaque aperçu passent par
  `get_stream_url`, le PTZ et l'IR par `can_control_ptz` (refus propre si
  le compte n'est plus rattaché au site) — tout est journalisé.

### Bande passante mosaïque (`StreamScheduler`)

Une mosaïque 4×4 ≠ 16 flux simultanés (aucune 4G/ADSL ne tient) :

- **Quota configurable de flux live** (défaut 4, réglage installateur
  par l'icône ⚙ de la page Caméras : 1 à 12, mémorisé) — les caméras
  au-delà passent en **snapshot JPG rafraîchi toutes les 5 s**
  (`/api/frame.jpeg` go2rtc), avec horodatage affiché.
- **Dégradation automatique** : la durée de récupération des snapshots
  sert de sonde — > 3 s (réseau saturé) = un flux live de moins ;
  < 1 s (réseau sain) = un flux de plus. Hystérésis 10 s, plancher 1 flux.
- **Sous-flux partout où c'est contrôlable** : les URLs NVR/ONVIF/ISAPI
  construites par l'app ciblent déjà le flux secondaire (~640×360) ;
  côté go2rtc, le `src` expose le sous-flux configuré serveur.
- **Repli par tuile** : un aperçu WebRTC qui échoue (NAT) bascule en
  snapshots sans interrompre la mosaïque.
- Les flux RTSP directs restent en placeholder dans la mosaïque (lecture
  plein écran au tap) : le RTSP local n'a pas de contrainte de débit.

---

## 7. Serveur vidéo go2rtc (`go2rtc/`)

`go2rtc.yaml` documente le montage complet :

- `api: :1984` (interface admin + flux HLS `/api/stream.m3u8?src=…`)
- **WebRTC/WHEP `/api/webrtc?src=…` — latence < 1 s** : l'app négocie
  toujours le WebRTC en premier pour les flux go2rtc et n'utilise le HLS
  (2-6 s) qu'en repli automatique si le NAT le refuse.
- `rtsp: :8554` (re-diffusion RTSP)
- section **CLOUD (P2P)** : préfixer les flux par le code boîtier
  (`EYE7F3K2-1`, `EYE7F3K2-2`…) pour l'appairage par code côté app.

```bash
cd go2rtc && ./restart.sh     # (re)démarrer le serveur
```

Transports de lecture affichés dans le direct : `WEBRTC <1S` (flutter_webrtc
via WHEP), `HLS` (repli), `RTSP` (direct NVR/caméra via media_kit).

---

## 8. Dépannage

| Symptôme | Cause probable |
|---|---|
| Pas de page de connexion sur l'APK | APK compilé sans dart-defines → utiliser `./build_apk.sh` |
| Direct go2rtc avec 2-6 s de retard | WebRTC échoué → repli HLS (voir badge) ; vérifier `/api/webrtc` (go2rtc >= 1.2) et le NAT/HTTPS |
| Badge HLS systématique en entreprise/4G | NAT symétrique — configurer un TURN (⚙ → Réglages réseau) |
| « Aucune caméra ONVIF trouvée » | Téléphone pas sur le WiFi du site, ou AP isolant les clients |
| Direct noir en IP directe | Redirection de port absente/fermée → bouton « Tester la connexion » |
| « Identifiants refusés » (ISAPI/ONVIF) | Digest refusé — vérifier le compte admin de l'appareil |
| « Accès au flux refusé » | Compte dissocié du site côté Supabase |
| Caméra « HORS LIGNE » | Hôte injoignable (TCP) — caméra éteinte, IP changée, réseau coupé |
| Mosaïque : tuiles « SNAPSHOT 5S » | Normal — quota de flux live atteint ; augmenter via ⚙ (technicien) ou attendre la récupération réseau |
| Replay vide alors que le NVR enregistre | Filtre de recherche à ±1 h (fuseaux) ou firmware exotique — vérifier `/ISAPI/ContentMgmt/search` dans un navigateur |
| Talk-back muet | Maintenir le bouton (appui long), autoriser le micro ; certains firmwares attendent G.711 A-law |

---

## 9. Stack technique

- **Flutter** (Material 3) — polices Plus Jakarta Sans + JetBrains Mono
- **Supabase** — auth, Postgres/RLS, realtime, storage (photos tickets), Edge
- **flutter_webrtc** — WebRTC/WHEP < 1 s (go2rtc), STUN/TURN configurables
- **media_kit** — lecture HLS (repli) et RTSP direct, accélération matérielle
- **record** — capture micro PCM 16 bits 8 kHz pour le talk-back (encodé
  G.711 par `lib/data/g711.dart`, portage CCITT) — écosystème 7.x avec
  `dependency_overrides: record_linux ^2.1.1` (le 5.x cassait la
  compilation via record_linux 0.7.2)
- **firebase_messaging** + `flutter_local_notifications` — push incidents
- **xml** + **crypto** (md5/sha1) — parsing SOAP/JSON-RPC et authentifications
- **Dart pur** pour les protocoles caméras : ONVIF (SOAP/WS-Security +
  Imaging), ISAPI/VAPIX/LAPI/Dahua HTTP (Digest MD5 partagé, certificats
  auto-signés), go2rtc (REST), WHEP — **zéro SDK natif constructeur**
- Permissions Android : INTERNET, réseau/WiFi (découverte ONVIF multicast),
  RECORD_AUDIO (talk-back)

Taille d'APK : ~47 Mo (arm64) dont ~12 Mo de libwebrtc natif — le prix de
la latence sub-secondaire.

---

## 10. Feuille de route (manques connus)

| Priorité | Sujet | État |
|---|---|---|
| 🔴 Critique | **Replay / enregistrements** | ✅ **ONVIF standard** (Recording Search — Dahua, Axis, Uniview, Hikvision) avec orchestration complète + **repli ISAPI** (Hikvision sans service standard). Navigateur de segments par jour, badge « · ONVIF », lecture media_kit, RETOUR DIRECT |
| 🔴 Critique | **Talk-back audio Hikvision** | ✅ Hikvision ISAPI (openTalk + talk-data chunked) — micro G.711 μ-law 8 kHz, maintenir le bouton 🎙. Permission RECORD_AUDIO |
| 🔴 Critique | **Talk-back multi-marques** | ⏳ Dahua, Axis, Uniview non couverts — le talk-back n'est pas standardisé ONVIF : adapter par marque (Dahua : HTTP audio API `audio.cgi` en PCM/G.711 ; Axis : VAPIX `aximg-cgi/audio.cgi` ; Uniview : LAPI audio). Suivre le patron G.711 déjà en place |
| 🔴 Critique | **Validation terrain (matériel réel)** | ⏳ AUCUN protocole n'a été testé sur caméra réelle — replay ONVIF, événements PullPoint, talk-back, PTZ, IR, Digest MD5/SHA-1 sont implémentés best-effort sur base de spécifications théoriques. Points de risque : variance firmware par marque/modèle, parseurs XML tolerants mais non vérifiés. **Bloquant pour la commercialisation** : tester chaque feature sur chaque marque du parc avant déploiement client |
| 🔴 Critique | **Alertes push intrusion (app fermée)** | ⏳ Une intrusion/tamper détectée n'alerte personne si aucune app n'est ouverte — le poller tourne côté app technicien uniquement. Solution : Edge Function Supabase (worker 24/7 qui poll les caméras + FCM vers les clients du site). L'infrastructure est prête : FCM câblé, table `camera_events` + Realtime en place — il ne manque que le worker |
| 🟠 Important | Événements ONVIF PullPoint | ✅ **livré** — pollers 3 s par caméra, anti-bruit (dédup 30 s + priorisation critique/mouvement + résumé multi-caméras), badge MOUVEMENT temps réel, persistance des critiques (`camera_events` + Realtime, migration 10) |
| 🟠 Important | Marques cloud-only (Ezviz, Tapo, Xiaomi) | 🟨 contournement : activer le RTSP local dans leur app (Tapo : réglages avancés ; Ezviz : selon modèles) puis URL SIMPLE. Intégration directe = leurs SDK cloud, hors périmètre actuel |
| 🟡 Moyen | Coffre-fort credentials | ⏳ les URLs RTSP restent en clair dans `equipment.stream_url` (limite documentée §5) ; verrouillage complet = passer par le relais + REVOKE |
| 🟡 Moyen | Mise à jour firmware distante | ⏳ ISAPI l'expose — après validation du talk-back/replay sur le terrain |
| 🟡 Moyen | Emails transactionnels | 🟨 SMTP intégré Supabase actif (limité 2-3/h) — prévoir domaine + Resend/Brevo à la montée en charge |
| 🟢 Long terme | ONVIF Profile V | 👀 veille — notre stack s'y aligne déjà (sortant + WebRTC) |

> Variance firmwares : le talk-back et la recherche d'enregistrements
> ISAPI peuvent varier selon les générations Hikvision — best-effort avec
> messages d'erreur explicites ; tester sur chaque modèle déployé.
