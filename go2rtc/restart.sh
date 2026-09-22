
#!/usr/bin/env bash
# Arrête proprement go2rtc puis le relance avec la config du projet.
set -u
cd "$(dirname "$0")"

# Arrêt : uniquement le binaire exact (pas de pkill générique qui
# peut s'auto-matcher).
for pid in $(pgrep -x go2rtc); do
  kill -9 "$pid" 2>/dev/null || true
done
sleep 2

# Relance en arrière-plan
nohup ./go2rtc > go2rtc.log 2>&1 &
echo "PID go2rtc : $!"
sleep 4

echo "── Streams déclarés ──"
curl -s http://127.0.0.1:1984/api/streams | python3 -m json.tool | head -25
echo "── Test HLS (entree) ──"
curl -s "http://127.0.0.1:1984/api/stream.m3u8?src=cocody_entree" | head -8
