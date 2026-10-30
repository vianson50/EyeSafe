// ═══════════════════════════════════════════════════════════
// Edge Function : maintenance-reminder
//
// Vérifie les visites de maintenance prévues dans 7 jours (J-7) et
// 1 jour (J-1), envoie une notification au propriétaire du site.
//
// Déployée via : supabase functions deploy maintenance-reminder --cron "0 8 * * *"
// ═══════════════════════════════════════════════════════════
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

Deno.serve(async () => {
  try {
    const today = new Date();
    const j7 = new Date(today.getTime() + 7 * 86400000).toISOString().split("T")[0];
    const j1 = new Date(today.getTime() + 1 * 86400000).toISOString().split("T")[0];

    const { data: visits } = await supabase
      .from("maintenance_visits")
      .select("id, site_id, scheduled_on, technician_name");

    const reminders = [];

    for (const visit of visits ?? []) {
      const d = visit.scheduled_on;
      const isJ7 = d === j7;
      const isJ1 = d === j1;

      if (!isJ7 && !isJ1) continue;

      // Trouve le propriétaire du site
      const { data: site } = await supabase
        .from("sites")
        .select("owner_id, name")
        .eq("id", visit.site_id)
        .single();

      if (!site?.owner_id) continue;

      await supabase.from("notifications").insert({
        user_id: site.owner_id,
        title: isJ1
          ? "Intervention demain"
          : "Intervention dans 7 jours",
        body: `${visit.technician_name} — ${isJ1 ? "demain" : "dans 7 jours} (${d})`,
        type: "maintenance",
        data: { visit_id: visit.id },
      });

      reminders.push({ visit_id: visit.id, type: isJ1 ? "J-1" : "J-7" });
    }

    return new Response(
      JSON.stringify({ ok: true, reminders }),
      { headers: { "Content-Type": "application/json" }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ ok: false, error: err.message }),
      { headers: { "Content-Type": "application/json" }
    );
  }
});
