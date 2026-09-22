-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Migration 6 : flux vidéo des caméras
--
-- Ajoute equipment.stream_url : URL de flux en direct (HLS ou RTSP)
-- consommée par l'onglet « Caméras » de l'application.
--
-- En production, on y stocke l'URL fournie par le serveur vidéo
-- (ex. go2rtc/MediaMTX qui expose les caméras en HLS/WebRTC), pas
-- l'URL RTSP brute du LAN (inaccessible depuis Internet).
-- ═══════════════════════════════════════════════════════════

alter table public.equipment
  add column if not exists stream_url text;

comment on column public.equipment.stream_url is
  'URL du flux en direct (HLS https://… ou rtsp://…) — null si non configuré.';
