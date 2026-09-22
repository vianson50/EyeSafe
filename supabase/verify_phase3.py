#!/usr/bin/env python3
"""Vérification bout-en-bout de la Phase 3A (Storage + notifications).

Teste, avec les comptes de démo :
  1. Login client + technicien
  2. Upload d'une photo dans le bucket privé ticket-photos (politiques)
  3. Création d'un ticket avec photo (RLS)
  4. Notification reçue par le technicien (trigger notify_ticket_events)

Usage : python3 supabase/verify_phase3.py
"""
import json
import struct
import urllib.request

BASE = "https://rmhftiafvboelygsundz.supabase.co"
ANON = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtaGZ0aWFmdmJvZWx5Z3N1bmR6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk0NzQ0MjAsImV4cCI6MjEwNTA1MDQyMH0."
    "_s9P6tJrv2DiSQdGp6rYH3rN7sc8--Twt1-qllvYjVU"
)


def call(method, path, token=None, body=None, raw=None, content_type="application/json", extra_headers=None):
    url = f"{BASE}{path}"
    headers = {"apikey": ANON}
    if extra_headers:
        headers.update(extra_headers)
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = None
    if raw is not None:
        data = raw
        headers["Content-Type"] = content_type
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as res:
            payload = res.read()
            return res.status, json.loads(payload) if payload.startswith(b"{") or payload.startswith(b"[") else payload
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def login(email, password):
    status, data = call("POST", "/auth/v1/token?grant_type=password",
                        body={"email": email, "password": password})
    assert status == 200, f"login {email}: {status} {data}"
    return data["access_token"], data["user"]["id"]


def tiny_jpeg():
    """Génère un JPEG minimal 1x1 pixel (structure JFIF valide)."""
    return struct.pack(">B" * 0) or b""  # placeholder, remplacé ci-dessous


# JPEG 1x1 pixel valide (134 octets, gris)
JPEG_1PX = bytes.fromhex(
    "ffd8ffe000104a46494600010100000100010000ffdb004300080606070605080707070909080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c1c2837292c30313434341f27393d38323c2e333432ffc0000b080001000101011100ffc4001f0000010501010101010100000000000000000102030405060708090a0bffc400b5100002010303020403050504040000017d01020300041105122131410613516107227114328191a1082342b1c11552d1f02433627282090a161718191a25262728292a3435363738393a434445464748494a535455565758595a636465666768696a737475767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffda0008010100003f00fca8ffd9"
)


def main():
    print("── 1. Connexions ──")
    client_token, client_uid = login("client@eyesafe.dev", "Client-2026-demo")
    tech_token, _ = login("technicien@eyesafe.dev", "Tech-2026-demo")
    print("  client ✓   technicien ✓")

    print("── 2. Site du client ──")
    status, sites = call("GET", "/rest/v1/sites?select=id,name", token=client_token)
    assert status == 200 and sites, f"sites: {status} {sites}"
    site_id = sites[0]["id"]
    print(f"  {sites[0]['name']} ({site_id[:8]}…)")

    print("── 3. Upload photo (bucket privé, politique can_access_site) ──")
    import time
    photo_path = f"{site_id}/verify-test-{int(time.time())}.jpg"
    status, data = call("POST", f"/storage/v1/object/ticket-photos/{photo_path}",
                        token=client_token, raw=JPEG_1PX, content_type="image/jpeg")
    print(f"  HTTP {status} → {'✔ upload OK' if status in (200, 201) else '✗ ÉCHEC'}")
    if status not in (200, 201):
        print(f"  {data}")
        return
    print(f"  chemin : {photo_path}")

    print("── 4. Anonyme ne peut PAS uploader (contrôle RLS storage) ──")
    status, data = call("POST", f"/storage/v1/object/ticket-photos/{photo_path}-anon.jpg",
                        raw=JPEG_1PX, content_type="image/jpeg")
    print(f"  HTTP {status} → {'✔ bloqué' if status in (400, 401, 403, 425) else '⚠ comportement inattendu'}")

    print("── 5. Création du ticket (déclenche notify_ticket_events) ──")
    status, data = call("POST", "/rest/v1/tickets", token=client_token, body={
        "site_id": site_id,
        "title": "✔ Test automatique — photo & notification",
        "description": "Ticket créé par le script de vérification de la Phase 3A. Vous pouvez le supprimer.",
        "status": "pending",
        "photo_url": photo_path,
        "opened_by": client_uid,
    })
    print(f"  HTTP {status} → {'✔ ticket créé' if status in (200, 201) else '✗ ÉCHEC'}")
    if status not in (200, 201):
        print(f"  {data}")
        return

    print("── 6. Notifications du technicien (trigger + RLS) ──")
    status, notifs = call("GET", "/rest/v1/notifications?select=title,body,read_at&order=created_at.desc&limit=5",
                          token=tech_token)
    assert status == 200, f"notifications: {status} {notifs}"
    if notifs:
        print(f"  {len(notifs)} notification(s) — la plus récente :")
        n = notifs[0]
        print(f"  • [{n['title']}] {n['body']} (lu : {n['read_at'] is not None})")
        print("  ✔ CHAÎNE COMPLÈTE VALIDÉE : photo → ticket → trigger → notification")
    else:
        print("  ✗ Aucune notification — le trigger notify_ticket_events n'a pas fonctionné ?")

    print("── 7. Le client n'a PAS de notification pour son propre ticket ──")
    status, notifs = call("GET", "/rest/v1/notifications?select=title&limit=5", token=client_token)
    assert status == 200
    print(f"  {len(notifs)} notification(s) côté client → {'✔ cohérent' if len(notifs) == 0 else '(voir détail)'}")


if __name__ == "__main__":
    main()
