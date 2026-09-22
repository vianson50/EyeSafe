#!/usr/bin/env python3
"""Crée un 2e site de démo (multi-sites) pour le client EYESAFE.

Ajoute « Boutique Marcory Zone 4 » avec quelques équipements et tickets
pour tester le sélecteur de sites dans l'app. Idempotent : ne fait rien
si le site existe déjà.

Usage : python3 supabase/add_second_site.py
"""
import json
import urllib.request
import urllib.error
from datetime import date, timedelta

BASE = "https://rmhftiafvboelygsundz.supabase.co"
ANON = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtaGZ0aWFmdmJvZWx5Z3N1bmR6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk0NzQ0MjAsImV4cCI6MjEwNTA1MDQyMH0."
    "_s9P6tJrv2DiSQdGp6rYH3rN7sc8--Twt1-qllvYjVU"
)
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

    print("── 2. Le site Marcory existe-t-il déjà ? ──")
    status, rows = call("GET", "/rest/v1/sites?select=id&name=eq.Boutique%20Marcory%20Zone%204", token=token)
    if rows:
        site_id = rows[0]["id"]
        status, existing = call("GET", f"/rest/v1/equipment?select=id&site_id=eq.{site_id}", token=token)
        if existing:
            print("  ℹ site déjà complet — rien à faire.")
            return
        print("  ℹ site existant mais vide → complétion…")
    else:
        print("  ✗ Aucun site → création…")

    if not rows:
        print("── 3. Création du site ──")
        status, data = call("POST", "/rest/v1/sites", token=token, body={
            "owner_id": uid,
            "name": "Boutique Marcory Zone 4",
            "address": "Zone 4, Marcory, Abidjan",
            "contract_plan": "Contrat Maintenance Essentiel",
            "contract_renews_on": str(date.today() + timedelta(days=400)),
        })
        assert status in (200, 201), f"site: {status} {data}"
        status, rows = call("GET", "/rest/v1/sites?select=id,name&name=eq.Boutique%20Marcory%20Zone%204", token=token)
        site_id = rows[0]["id"]
        print(f"  ✔ {rows[0]['name']} ({site_id[:8]}…)")

    today = date.today()
    print("── 4. Équipements ──")
    equipment = [
        ("Caméra dôme vitrine", "Hikvision DS-2CD2143G2-I", "HK-2143-99111-M", "Vitrine principale", "camera", 200, 530, None, None),
        ("Caméra caisse", "Dahua IPC-HDW2441T", "DH-2441-77222-N", "Comptoir", "camera", 200, 530, None, None),
        ("NVR 8 canaux", "Hikvision DS-7608NI-K2", "HK-7608-31333-P", "Arrière-boutique", "recorder", 200, 530, None, None),
        ("Disque NVR 2 TO", "WD Purple WD20PURZ", "WD-20PZ-55444-R", "NVR", "storage", 200, None, 74.00, "2 TO"),
    ]
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

    print("── 5. Un ticket ouvert ──")
    status, eq = call("GET", f"/rest/v1/equipment?select=id&serial=eq.HK-2143-99111-M&site_id=eq.{site_id}", token=token)
    assert status == 200 and eq
    status, data = call("POST", "/rest/v1/tickets", token=token, body={
        "site_id": site_id, "equipment_id": eq[0]["id"],
        "title": "Image floue caméra vitrine",
        "description": "L'image de la vitrine est floue depuis quelques jours, nettoyage nécessaire.",
        "status": "pending", "opened_by": uid,
    })
    assert status in (200, 201), f"ticket: {status} {data}"
    print("  ✔ ticket créé (le technicien est notifié)")

    print("── 6. Une visite planifiée ──")
    status, data = call("POST", "/rest/v1/maintenance_visits", token=token, body={
        "site_id": site_id, "technician_id": TECH_ID,
        "technician_name": "Konan Y. — Technicien certifié",
        "scheduled_on": str(today + timedelta(days=12)),
        "tasks": ["Nettoyage objectifs (2 caméras)", "Contrôle NVR"], "report_ref": None,
    })
    assert status in (200, 201), f"visite: {status} {data}"
    print("  ✔ visite planifiée")

    print("── 7. Assignation du technicien ──")
    status, data = call("POST", "/rest/v1/site_technicians", token=token,
                        body={"site_id": site_id, "technician_id": TECH_ID})
    print(f"  {'✔ technicien assigné' if status in (200, 201) else f'⚠ {status} {data}'}")

    print("\n🏬 2e site créé ! Rouvrez l'app → la sidebar affiche « 2 sites ▾ »")


if __name__ == "__main__":
    main()
