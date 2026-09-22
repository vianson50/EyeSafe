#!/usr/bin/env python3
"""Démonstration de l'isolement multi-clients EYESAFE.

1. Crée un second client (marcory@eyesafe.dev), propriétaire de la
   Boutique Marcory Zone 4 (transfert de propriété via service_role).
2. Vérifie l'isolement RLS :
   - client@eyesafe.dev       → ne voit QUE Cocody
   - marcory@eyesafe.dev      → ne voit QUE Marcory
   - technicien@eyesafe.dev   → voit les DEUX sites + les tickets
Usage : python3 supabase/multi_tenant_demo.py
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
SERVICE = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtaGZ0aWFmdmJvZWx5Z3N1bmR6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4OTQ3NDQyMCwiZXhwIjoyMTA1MDUwNDIwfQ."
    "VelgR_S5pzh6MBYyiJYawKx8GWiicx14-yrsK2wDssI"
)


def call(method, path, key, token=None, body=None):
    headers = {"apikey": key, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{BASE}{path}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as res:
            p = res.read()
            return res.status, json.loads(p) if p else None
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def login(email, password):
    status, data = call("POST", "/auth/v1/token?grant_type=password", ANON,
                        body={"email": email, "password": password})
    assert status == 200, f"login {email}: {status} {data}"
    return data["access_token"], data["user"]["id"]


def main():
    # ── 1. Création du second client ──
    print("── 1. Création du client Marcory ──")
    status, data = call("POST", "/auth/v1/admin/users", SERVICE, token=SERVICE, body={
        "email": "marcory@eyesafe.dev",
        "password": "Marcory-2026-demo",
        "email_confirm": True,
        "user_metadata": {"full_name": "Client Marcory"},
    })
    if status in (200, 201):
        marcory_uid = data["id"]
        print(f"  ✔ marcory@eyesafe.dev créé ({marcory_uid[:8]}…)")
    elif status == 422:
        status, data = call("GET", "/auth/v1/admin/users?email=marcory@eyesafe.dev", SERVICE, token=SERVICE)
        marcory_uid = data["users"][0]["id"]
        print(f"  ℹ déjà existant ({marcory_uid[:8]}…)")
    else:
        raise SystemExit(f"échec création: {status} {data}")

    # ── 2. Transfert de propriété du site Marcory ──
    print("── 2. Transfert de « Boutique Marcory Zone 4 » ──")
    status, rows = call("GET", "/rest/v1/sites?select=id,owner_id&name=eq.Boutique%20Marcory%20Zone%204",
                        SERVICE, token=SERVICE)
    site_id, old_owner = rows[0]["id"], rows[0]["owner_id"]
    if old_owner != marcory_uid:
        status, data = call("PATCH", f"/rest/v1/sites?id=eq.{site_id}", SERVICE,
                            token=SERVICE, body={"owner_id": marcory_uid})
        assert status in (200, 204), f"transfert: {status} {data}"
        print("  ✔ propriété transférée au client Marcory")
    else:
        print("  ℹ déjà propriétaire")

    # ── 3. Vérification de l'isolement ──
    print("\n═══ VÉRIFICATION DE L'ISOLEMENT (RLS) ═══")

    t_client1, uid1 = login("client@eyesafe.dev", "Client-2026-demo")
    t_marcory, _ = login("marcory@eyesafe.dev", "Marcory-2026-demo")
    t_tech, _ = login("technicien@eyesafe.dev", "Tech-2026-demo")

    print("\n▸ client@eyesafe.dev (Cocody) :")
    s, sites = call("GET", "/rest/v1/sites?select=name", ANON, token=t_client1)
    for x in sites:
        print(f"   site visible : {x['name']}")
    s, stolen = call("GET", f"/rest/v1/equipment?select=id&site_id=eq.{site_id}", ANON, token=t_client1)
    print(f"   équipements de Marcory visibles : {len(stolen)} (attendu 0)")

    print("\n▸ marcory@eyesafe.dev (Marcory) :")
    s, sites = call("GET", "/rest/v1/sites?select=name", ANON, token=t_marcory)
    for x in sites:
        print(f"   site visible : {x['name']}")
    s, own = call("GET", f"/rest/v1/equipment?select=id&site_id=eq.{site_id}", ANON, token=t_marcory)
    print(f"   ses équipements visibles : {len(own)} (attendu 4)")

    print("\n▸ technicien@eyesafe.dev (Konan Y.) :")
    s, sites = call("GET", "/rest/v1/sites?select=name&order=created_at", ANON, token=t_tech)
    for x in sites:
        print(f"   site visible : {x['name']}")
    s, tickets = call("GET", "/rest/v1/tickets?select=title,status&order=opened_at.desc", ANON, token=t_tech)
    print(f"   tickets de TOUS les sites : {len(tickets)}")
    for t in tickets[:4]:
        print(f"   • [{t['status']}] {t['title']}")


if __name__ == "__main__":
    main()
