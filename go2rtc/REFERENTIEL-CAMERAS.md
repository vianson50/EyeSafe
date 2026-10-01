# ═══════════════════════════════════════════════════════════
# RÉFÉRENTIEL CAMÉRAS — Marques, URLs RTSP, ports, config
#
# Le guide complet pour connecter N'IMPORTE quelle caméra dans
# l'app EyeSafe. Classé par marque avec les URLs exactes.
# ═══════════════════════════════════════════════════════════

---

## 📊 TYPES D'ENREGISTREURS (DVR / NVR / XVR)

| Type | Caméras acceptées | Câblage | Réseau |
|---|---|---|---|
| **DVR** | Analogiques (BNC/coaxial) | Coaxial | Ethernet pour l'accès distant |
| **NVR** | IP (PoE ou WiFi) | Ethernet RJ45 | Ethernet |
| **XVR** | Hybride (analogique + IP) | Coaxial + Ethernet | Ethernet |
| **Aucun** | IP/WiFi autonomes | Ethernet ou WiFi | WiFi ou Ethernet |

> 💡 **XVR** = le plus polyvalent — accepte tout. Ton client peut avoir
> un XVR sans le savoir (c'est souvent marqué "Hybrid" ou "5-in-1").

---

## 🎯 COMMENT IDENTIFIER UNE CAMÉRA (30 secondes)

| Indice | Marque probable |
|---|---|
| Logo bleu/blanc "HIKVISION" | Hikvision |
| Logo noir/or "DAHUA" ou "IMOU" | Dahua / Imou |
| Logo "AXIS" (Suède) | Axis |
| Logo "UNIVIEW" ou "IPC-xxx" | Uniview |
| Logo "TP-LINK" VIGI | TP-Link Vigi |
| Logo "EZVIZ" | Ezviz (filiale Hikvision) |
| Logo "XIAOMI" | Xiaomi |
| Logo "CP Plus" | CP Plus (Inde, compatible Hikvision) |
| Logo "HILOOK" | HiLook (filiale Hikvision) |
| Rien / générique chinois | Souvent compatible ONVIF |

---

# ═══════════════════════════════════════════════════════════
# URLs RTSP PAR MARQUE (copier-coller dans URL SIMPLE)
# ═══════════════════════════════════════════════════════════

## 1. HIKVISION / HILOOK / EZVIZ

### Caméra IP seule
```
Flux principal : rtsp://utilisateur:motdepasse@IP:554/Streaming/Channels/101
Flux secondaire : rtsp://utilisateur:motdepasse@IP:554/Streaming/Channels/102

→ 101 = caméra 1, flux principal
→ 102 = caméra 1, flux secondaire (léger)
→ 201 = caméra 2, flux principal
→ 202 = caméra 2, flux secondaire
```

### NVR (plusieurs caméras)
```
rtsp://utilisateur:motdepasse@IP_NVR:554/Streaming/Channels/101  (caméra 1)
rtsp://utilisateur:motdepasse@IP_NVR:554/Streaming/Channels/201  (caméra 2)
rtsp://utilisateur:motdepasse@IP_NVR:554/Streaming/Channels/301  (caméra 3)
```

### Ports par défaut
| Port | Usage |
|---|---|
| 554 | RTSP (flux vidéo) |
| 8000 | SDK Hikvision |
| 80 | HTTP (interface web) |

### Identifiants par défaut
| Modèle | Utilisateur | Mot de passe |
|---|---|---|
| Hikvision ancien | admin | 12345 |
| Hikvision récent | admin | (étiquette sur le NVR) |
| HiLook | admin | (étiquette) |
| Ezviz | (app mobile) | (QR code) |

### Dans l'app EyeSafe
- Mode : **NVR LOCAL** → marque Hikvision
- OU : **ONVIF** (découverte automatique)
- OU : **API MARQUE** → ISAPI (deviceInfo, PTZ, motion)

---

## 2. DAHUA / IMOU

### Caméra IP seule
```
Flux principal : rtsp://utilisateur:motdepasse@IP:554/cam/realmonitor?channel=1&subtype=0
Flux secondaire : rtsp://utilisateur:motdepasse@IP:554/cam/realmonitor?channel=1&subtype=1

→ channel=1 (2, 3…) = numéro de la caméra
→ subtype=0 = principal (HD)
→ subtype=1 = secondaire (léger, mobile)
```

### NVR
```
rtsp://utilisateur:motdepasse@IP_NVR:554/cam/realmonitor?channel=1&subtype=1
rtsp://utilisateur:motdepasse@IP_NVR:554/cam/realmonitor?channel=2&subtype=1
```

### Ports par défaut
| Port | Usage |
|---|---|
| 554 | RTSP |
| 37777 | SDK Dahua |
| 37778 | HTTP (interface) |

### Identifiants par défaut
| Modèle | Utilisateur | Mot de passe |
|---|---|---|
| Dahua ancien | admin | admin |
| Dahua récent | admin | (étiquette ou admin admin) |
| Imou | admin | (étiquette/QR code) |

### Dans l'app EyeSafe
- Mode : **NVR LOCAL** → marque Dahua
- OU : **ONVIF** (fonctionne très bien avec Dahua)
- OU : **API MARQUE** → Dahua HTTP (login 2 temps)

---

## 3. AXIS

### Caméra IP
```
Flux simple : rtsp://utilisateur:motdepasse@IP:554/axis-media/media.amp
Avec qualité : rtsp://utilisateur:motdepasse@IP:554/axis-media/media.amp?videocodec=h264&resolution=640x360
Caméra N : rtsp://utilisateur:motdepasse@IP:554/axis-media/media.amp?camera=1
```

### Ports par défaut
| Port | Usage |
|---|---|
| 554 | RTSP |
| 80 | HTTP (VAPIX) |

### Identifiants par défaut
| Utilisateur | Mot de passe |
|---|---|
| root | pass (ancien) ou (étiquette) |

### Dans l'app EyeSafe
- Mode : **API MARQUE** → VAPIX (param.cgi, Digest MD5)
- OU : **ONVIF** (excellente compatibilité Axis)
- OU : **URL SIMPLE** avec l'URL ci-dessus

---

## 4. UNIVIEW

### Caméra IP
```
Flux principal : rtsp://utilisateur:motdepasse@IP:554/media/video1
Flux secondaire : rtsp://utilisateur:motdepasse@IP:554/media/video2
```

### NVR
```
rtsp://utilisateur:motdepasse@IP_NVR:554/unicast/c1/s0/live  (caméra 1, principal)
rtsp://utilisateur:motdepasse@IP_NVR:554/unicast/c1/s1/live  (caméra 1, secondaire)
rtsp://utilisateur:motdepasse@IP_NVR:554/unicast/c2/s1/live  (caméra 2, secondaire)
```

### Ports par défaut
| Port | Usage |
|---|---|
| 554 | RTSP |
| 80 | HTTP (LAPI) |

### Identifiants par défaut
| Utilisateur | Mot de passe |
|---|---|
| admin | admin ou (étiquette) |

### Dans l'app EyeSafe
- Mode : **NVR LOCAL** → marque Uniview
- OU : **API MARQUE** → LAPI (JSON)
- OU : **ONVIF**

---

## 5. TP-LINK VIGI

### Caméra IP
```
rtsp://utilisateur:motdepasse@IP:554/stream1  (principal)
rtsp://utilisateur:motdepasse@IP:554/stream2  (secondaire)
```

### Ports
| Port | Usage |
|---|---|
| 554 | RTSP |
| 80 | HTTP |
| 2020 | VIGI app |

### Identifiants par défaut
| Utilisateur | Mot de passe |
|---|---|
| admin | (étiquette QR code) |

### Dans l'app EyeSafe
- Mode : **URL SIMPLE** avec l'URL ci-dessus
- OU : **ONVIF** (compatible)

---

## 6. XIAOMI / IMOU (Wi-Fi)

### Xiaomi (caméras Wi-Fi)
```
⚠️ RTSP non activé par défaut → il faut le DVR/NVR ou une
   app tierce. Activable via l'app Mi Home (paramètres avancés).
```

### Imou (Wi-Fi)
```
Flux : rtsp://utilisateur:motdepasse@IP:554/cam/realmonitor?channel=1&subtype=1
(même format que Dahua — Imou est une filiale)
```

### Dans l'app EyeSafe
- Mode : **URL SIMPLE** (si RTSP activé)
- Sinon : il faut un NVR qui les intègre

---

## 7. CP PLUS (Inde, très courant en Afrique)

```
Compatible Hikvision — mêmes URLs :
rtsp://utilisateur:motdepasse@IP:554/Streaming/Channels/101
```

### Dans l'app EyeSafe
- Mode : **NVR LOCAL** → marque Hikvision

---

## 8. MARQUES GÉNÉRIQUES CHINOISES

Beaucoup de caméras "no-name" respectent le standard ONVIF :

```
URL ONVIF générique : rtsp://utilisateur:motdepasse@IP:554/onvif1
OU : rtsp://utilisateur:motdepasse@IP:554/live/ch00_0
OU : rtsp://utilisateur:motdepasse@IP:554/h264_stream
```

### Dans l'app EyeSafe
- Mode : **ONVIF** (découverte + GetStreamUri → l'app trouve l'URL)
- OU : **URL SIMPLE** (essaie les URLs ci-dessus)

---

# ═══════════════════════════════════════════════════════════
# TABLEAU RÉCAPITULATIF — Quelle marque, quel mode dans l'app ?
# ═══════════════════════════════════════════════════════════

| Marque | Mode recommandé | Mode alternatif | API dédiée |
|---|---|---|---|
| **Hikvision** | NVR LOCAL | ONVIF + ISAPI | ✅ ISAPI |
| **HiLook** | NVR LOCAL (comme Hikvision) | ONVIF | — |
| **Ezviz** | ONVIF | URL SIMPLE | — (cloud only) |
| **Dahua** | NVR LOCAL | ONVIF + HTTP API | ✅ HTTP 2 temps |
| **Imou** | NVR LOCAL (comme Dahua) | URL SIMPLE | — (cloud only) |
| **Axis** | API MARQUE (VAPIX) | ONVIF | ✅ VAPIX |
| **Uniview** | NVR LOCAL | ONVIF + LAPI | ✅ LAPI |
| **TP-Link VIGI** | URL SIMPLE | ONVIF | — |
| **Xiaomi** | (activer RTSP d'abord) | URL SIMPLE | — (cloud only) |
| **CP Plus** | NVR LOCAL (comme Hikvision) | ONVIF | — |
| **Générique** | ONVIF | URL SIMPLE | — |

---

# ═══════════════════════════════════════════════════════════
# DÉPANNAGE PAR SYMPTÔME
# ═══════════════════════════════════════════════════════════

## « Le flux ne s'affiche pas »

| Cause probable | Solution |
|---|---|
| Mauvais port | Essaie 554 puis 80 puis 8554 |
| Mauvais mot de passe | Vérifie l'étiquette du NVR |
| Caméra éteinte/injoignable | Ping l'IP depuis un PC |
| Codec non supporté | Essaie le flux secondaire (subtype=1 ou 102) |
| URL incorrecte | Utilise ONVIF (découverte auto) |

## « Le direct est lent »

| Cause | Solution |
|---|---|
| Flux principal trop lourd | Utilise le flux secondaire |
| Réseau WiFi saturé | Passe en Ethernet |
| Pas de relais go2rtc | Le RTSP direct est lent sur mobile — normal |

## « La découverte ONVIF ne trouve rien »

| Cause | Solution |
|---|---|
| Téléphone pas sur le même réseau | Connecte-toi au WiFi du client |
| Caméra non-ONVIF | Utilise URL SIMPLE avec l'URL de la marque |
| Multicast bloqué | Essaie l'IP manuelle + ONVIF |

---

# ═══════════════════════════════════════════════════════════
# CONFIGURATIONS SPÉCIALES
# ═══════════════════════════════════════════════════════════

## Caméra avec redirection de port (accès distant)

```
Chez le client : routeur → rediriger port 554 vers IP_caméra:554

URL dans l'app :
rtsp://utilisateur:motdepasse@IP_PUBLIQUE_CLIENT:554/Streaming/Channels/102
```

→ Mode : **IP / DOMAINE** (avec test de connexion intégré)

## Caméra via go2rtc (relais)

```
go2rtc (sur ton PC ou VPS) → récupère le RTSP → rediffuse en HLS/WebRTC

URL dans l'app :
http://IP_GO2RTC:1984/api/stream.m3u8?src=nom_du_flux
```

→ Mode : **RELAI GO2RTC** ou **CLOUD (P2P)**

## NVR avec plusieurs marques de caméras

```
Le NVR accepte des caméras de marques différentes (ONVIF)
→ Connecte toutes les caméras au NVR (via son interface web)
→ Puis dans l'app : connecte le NVR (une seule fois)
→ Toutes les caméras apparaissent ✅
```

---

# ═══════════════════════════════════════════════════════════
# MÉMO — Numéros de ports les plus courants
# ═══════════════════════════════════════════════════════════

| Port | Usage | Marques |
|---|---|---|
| **554** | RTSP (vidéo) | Toutes |
| **80** | HTTP (interface web) | Toutes |
| **443** | HTTPS | Toutes |
| **8000** | SDK | Hikvision |
| **8080** | HTTP alternatif | Generic |
| **37777** | SDK | Dahua |
| **37778** | HTTP | Dahua |
| **8899** | RTSP alternatif | Certaines génériques |
| **8554** | RTSP go2rtc | go2rtc |
| **1984** | API go2rtc | go2rtc |
| **5000** | Interface Frigate | Frigate |
