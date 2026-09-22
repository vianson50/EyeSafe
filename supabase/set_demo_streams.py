#!/usr/bin/env python3
"""Active des flux HLS de démonstration sur les caméras EYESAFE.

En production, ces URL seront remplacées par celles du serveur vidéo
(go2rtc/MediaMTX) qui expose les vraies caméras. Ici on utilise des
flux publics de test pour valider l'onglet « Caméras ».

Usage : python3 supabase/set_demo_streams.py
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

# Flux publics de test (HLS) — alternés entre les caméras.
STREAMS = [
    "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
    "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_hls/master.m3u8",
    "https://test-streams.mux.dev/pts_shift/master.m3u8",
]


def call(method, path, token=None, body=None):
    headers = {"apikey": ANON, "Content-Type": "application/json"}
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


def main():
    print("── 1. Login technicien (accès aux deux sites) ──")
    status, data = call("POST", "/auth/v1/token?grant_type=password",
                        body={"email": "technicien@eyesafe.dev", "password": "Tech-2026-demo"})
    assert status == 200, f"login: {status} {data}"
    token = data["access_token"]

    print("── 2. Caméras sans flux ──")
    status, cameras = call("GET",
        "/rest/v1/equipment?select=id,name,site_id,stream_url&category=eq.camera&order=name",
        token=token)
    assert status == 200, cameras
    todo = [c for c in cameras if not c.get("stream_url")]
    if not todo:
        print("  ℹ toutes les caméras ont déjà un flux — rien à faire.")
        return
    print(f"  {len(todo)} caméra(s) à équiper")

    for i, cam in enumerate(todo):
        url = STREAMS[i % len(STREAMS)]
        status, d = call("PATCH", f"/rest/v1/equipment?id=eq.{cam['id']}", token,
                         body={"stream_url": url})
        ok = status in (200, 204)
        print(f"  {'✔' if ok else '✗'} {cam['name']} → {url.split('/')[2]} ({status})")


if __name__ == "__main__":
    main()
