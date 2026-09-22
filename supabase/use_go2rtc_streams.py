#!/usr/bin/env python3
"""Pointe les caméras du site Cocody vers le serveur go2rtc local.

Après ce script, l'onglet « Caméras » de l'app (téléphone sur le même
WiFi que le PC) lit les flux servis par go2rtc (http://192.168.100.14:1984)
— exactement le schéma de production, où l'IP sera celle du serveur
du client.

Usage : python3 supabase/use_go2rtc_streams.py
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
GO2RTC = "http://192.168.100.14:1984/api/stream.m3u8?src="

# caméra (par nom) → nom du flux go2rtc
MAPPING = {
    "Caméra dôme entrée": "cocody_entree",
    "Caméra tube parking": "cocody_parking",
}


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
    print("── 1. Login client (Cocody) ──")
    status, data = call("POST", "/auth/v1/token?grant_type=password",
                        body={"email": "client@eyesafe.dev", "password": "Client-2026-demo"})
    assert status == 200, data
    token = data["access_token"]

    print("── 2. Caméras du site ──")
    status, cameras = call(
        "GET", "/rest/v1/equipment?select=id,name&category=eq.camera&order=name",
        token=token)
    assert status == 200, cameras

    print("── 3. Pointage vers go2rtc ──")
    for cam in cameras:
        src = MAPPING.get(cam["name"])
        if not src:
            continue
        url = GO2RTC + src
        status, d = call("PATCH", f"/rest/v1/equipment?id=eq.{cam['id']}", token,
                         body={"stream_url": url})
        ok = status in (200, 204)
        print(f"  {'✔' if ok else '✗'} {cam['name']} → {url} ({status})")

    print("\n📱 Téléphone sur le MÊME WiFi que le PC → onglet Caméras → direct !")


if __name__ == "__main__":
    main()
