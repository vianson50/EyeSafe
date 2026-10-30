// ═══════════════════════════════════════════════════════════
// Edge Function : health-check
// Vérifie l'état TCP de chaque équipement avec stream_url et écrit dans equipment_health.
// Déployée via : supabase functions deploy health-check --cron "*/5 * * * *"
// ═══════════════════════════════════════════════════════════
Deno.serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Récupère tous les équipements avec flux
  const { data: equipment } = await supabase
    .from("equipment")
    .select("id, site_id, stream_url");

  for (const e of equipment ?? []) {
    if (!e.stream_url) continue;

    const url = new URL(e.stream_url);
    const port = url.port || 554;
    const start = Date.now();

    let online = false;
    let latency = null;
    try {
      // Tentative TCP
      const conn = await Deno.connect({
        hostname: url.hostname,
        port: parseInt(port);
      });
      conn.close();
      online = true;
      latency = Date.now() - start;
    } catch (_e) {
      online = false;
    }

    // Écrit le résultat
    await supabase.from("equipment_health").insert({
      equipment_id: e.id,
      site_id: e.site_id,
      online,
      latency_ms: latency,
    });

    // Alerte FCM si l'équipement vient de tomber
    if (!online) {
      const { data: prev } = await supabase
        .from("equipment_health")
        .select("online")
        .eq("equipment_id", e.id)
        .order("created_at", { ascending: false })
        .limit(2);
      // Si l'équipement était en ligne avant → notification
      if (prev && prev.length > 1 && prev[1]?.online) {
        await supabase.from("notifications").insert({
          user_id: e.site_id, // simplifié : notifier le propriétaire
          title: "Équipement hors ligne",
          body: "Un équipement vient de tomber hors ligne.",
          type: "equipment_down",
          data: { equipment_id: e.id },
        });
      }
    }
  }

  return new Response(JSON.stringify({ ok: true }),
    { headers: { "Content-Type": "application/json" }
  });
});
