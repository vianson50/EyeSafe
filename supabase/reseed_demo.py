#!/usr/bin/env python3
"""Diagnostic + réinjection des données de démo EYESAFE.

Si le client ne possède aucun site (message « Aucun site associé à
votre compte »), ce script recrée le site de démo ivoirien et toutes
ses données VIA L'API REST, en respectant la RLS — exactement comme
le ferait l'application.

Usage : python3 supabase/reseed_demo.py
"""
import json
import urllib.request
import urllib.error

BASE = "https://rmhftiafvboelygsundz.supabase.co"
ANON = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtaGZ0aWFmdmJvZWx5Z3N1bmR6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk0NzQ0MjAsImV4cCI6MjEwNTA1MDQyMH0."
    "_s9P6tJrv2DiSQdGp6rYH3rN7sc8--Twt1-qllvYjVU"
)
# UUID connus (sortie de create_users.sh)
TECH_ID = "6c10c5ee-7ffb-49c5-bc4b-042cc02a603b"


def call(method, path, token=None, body=None):
    headers = {"apikey": ANON}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    if data:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{BASE}{path}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as res:
            payload = res.read()
            return res.status, json.loads(payload) if payload else None
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def main():
    print("── 1. Login client ──")
    status, data = call("POST", "/auth/v1/token?grant_type=password",
                        body={"email": "client@eyesafe.dev", "password": "Client-2026-demo"})
    assert status == 200, f"login: {status} {data}"
    token, uid = data["access_token"], data["user"]["id"]
    print(f"  connecté ({uid[:8]}…)")

    print("── 2. Diagnostic : sites du client ──")
    status, sites = call("GET", "/rest/v1/sites?select=id,name&order=created_at", token=token)
    assert status == 200, f"sites: {status} {sites}"
    site_id = None
    if sites:
        print(f"  ℹ {len(sites)} site(s) existant(s) :")
        for s in sites:
            print(f"    • {s['name']}")
        site_id = sites[0]["id"]
        status, eq_count = call("GET", f"/rest/v1/equipment?select=id&site_id=eq.{site_id}", token=token)
        if eq_count:
            print(f"  → Site déjà rempli ({len(eq_count)} équipements) — rien à faire.")
            return
        print("  → Site vide → complétion des données")
    else:
        print("  ✗ Aucun site → création + réinjection des données de démo ivoiriennes")

    if site_id is None:
        print("── 3. Création du site ──")
        status, data = call("POST", "/rest/v1/sites", token=token, body={
            "owner_id": uid,
            "name": "Boutique Cocody Angré",
            "address": "Rue L112, Cocody Angré, Abidjan",
            "contract_plan": "Contrat Maintenance Premium",
            "contract_renews_on": "2027-03-15",
        })
        assert status in (200, 201), f"site: {status} {data}"
        status, rows = call("GET", "/rest/v1/sites?select=id,name&order=created_at&limit=1", token=token)
        assert status == 200 and rows, f"relecture site: {status} {rows}"
        site_id = rows[0]["id"]
        print(f"  ✔ {rows[0]['name']} ({site_id[:8]}…)")

    print("── 4. Équipements ──")
    equipment = [
        ("Caméra dôme entrée", "Hikvision DS-2CD2143G2-I", "HK-2143-88421-A", "Entrée principale", "camera", 420, 510, None, None),
        ("Caméra tube parking", "Dahua IPC-HFW2441T", "DH-2441-51702-B", "Parking extérieur", "camera", 420, 62, None, None),
        ("Caméra PTZ entrepôt", "Axis P3265-LV", "AX-3265-90347-C", "Entrepôt", "camera", 210, 720, None, None),
        ("Caméra caisse", "Hikvision DS-2CD2087G2H", "HK-2087-33918-D", "Zone caisse", "camera", 1180, None, None, None),
        ("NVR principal 32 canaux", "Hikvision DS-7732NI-K4", "HK-7732-10455-E", "Local technique", "recorder", 420, 510, None, None),
        ("Disque NVR 4 TO", "WD Purple WD40PURZ", "WD-40PZ-77213-F", "NVR — baie 1", "storage", 420, None, 68.00, "4 TO"),
        ("Disque NVR 4 TO (miroir)", "WD Purple WD40PURZ", "WD-40PZ-77214-G", "NVR — baie 2", "storage", 210, None, 68.00, "4 TO"),
        ("Switch PoE 16 ports", "TP-Link TL-SG1216P", "TP-1216-60892-H", "Local technique", "network", 420, 40, None, None),
    ]
    from datetime import date, timedelta
    today = date.today()
    for name, model, serial, loc, cat, installed, warranty, used, total in equipment:
        body = {
            "site_id": site_id, "name": name, "model": model, "serial": serial,
            "location": loc, "category": cat,
            "installed_on": str(today - timedelta(days=installed)),
            "storage_used_pct": used, "storage_total_label": total,
        }
        if warranty is not None:
            body["warranty_until"] = str(today + timedelta(days=warranty))
        status, data = call("POST", "/rest/v1/equipment", token=token, body=body)
        assert status in (200, 201), f"equipment {name}: {status} {data}"
    print(f"  ✔ {len(equipment)} équipements")

    print("── 5. Tickets ──")
    serials = {"DH-2441-51702-B": ("Caméra déplacée — angle mort",
                                    "La caméra du parking semble avoir été déplacée, une partie du parking n'est plus visible.", "en_route"),
               "HK-7732-10455-E": ("Écran noir sur visionnage mobile",
                                    "Le flux distant reste noir depuis l'application mobile ce matin.", "pending"),
               "HK-2087-33918-D": ("Câble détérioré caméra caisse",
                                    "Gainé plastique abîmé près du connecteur, image qui scintille.", "resolved")}
    for serial, (title, desc, st) in serials.items():
        s, eq = call("GET", f"/rest/v1/equipment?select=id&serial=eq.{serial}&site_id=eq.{site_id}", token=token)
        assert s == 200 and eq, f"equip {serial}: {s} {eq}"
        s, d = call("POST", "/rest/v1/tickets", token=token, body={
            "site_id": site_id, "equipment_id": eq[0]["id"], "title": title,
            "description": desc, "status": st, "opened_by": uid,
        })
        assert s in (200, 201), f"ticket {title}: {s} {d}"
    print("  ✔ 3 tickets (les techniciens sont notifiés par le trigger)")

    print("── 6. Visites d'entretien ──")
    visits = [
        (24, ["Nettoyage des objectifs (4 caméras)", "Contrôle alimentation & onduleur",
              "Vérification santé des disques", "Mise à jour firmware NVR"], None),
        (-96, ["Nettoyage des objectifs", "Contrôle alimentation & onduleur",
               "Vérification santé des disques"], "RPT-2025-118"),
        (-188, ["Réalignement caméra PTZ", "Contrôle général du site"], "RPT-2025-092"),
    ]
    for offset, tasks, report in visits:
        s, d = call("POST", "/rest/v1/maintenance_visits", token=token, body={
            "site_id": site_id, "technician_id": TECH_ID if report is None or offset > 0 else None,
            "technician_name": "Konan Y. — Technicien certifié" if offset != -188 else "Aya K. — Technicienne certifiée",
            "scheduled_on": str(today + timedelta(days=offset)),
            "tasks": tasks, "report_ref": report,
        })
        assert s in (200, 201), f"visite {offset}: {s} {d}"
    print("  ✔ 3 visites")

    print("── 7. Alertes ──")
    alerts = [
        ("Espace disque du NVR", "Le disque du NVR atteint 68 % de remplissage. Pensez à vérifier la durée de rétention.", "warning", "storage"),
        ("Coupure réseau détectée", "Le switch PoE a redémarré hier à 03h12. Aucune perte d'enregistrement constatée.", "info", "wifi_off"),
        ("Nettoyage des objectifs recommandé", "La caméra du parking n'a pas été nettoyée depuis plus de 6 mois.", "info", "cleaning_services"),
    ]
    for title, msg, sev, icon in alerts:
        s, d = call("POST", "/rest/v1/alerts", token=token, body={
            "site_id": site_id, "title": title, "message": msg,
            "severity": sev, "icon_hint": icon,
        })
        assert s in (200, 201), f"alerte {title}: {s} {d}"
    print("  ✔ 3 alertes (client + technicien notifiés)")

    print("── 8. Assignation du technicien ──")
    s, d = call("POST", "/rest/v1/site_technicians", token=token,
                body={"site_id": site_id, "technician_id": TECH_ID})
    print(f"  {'✔ technicien assigné' if s in (200, 201) else f'⚠ {s} {d}'}")

    print("\n🎉 RÉINJECTION TERMINÉE — rouvrez l'app et reconnectez-vous.")


if __name__ == "__main__":
    main()
