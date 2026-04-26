import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization) return jsonResponse({ error: "Unauthorized" }, 401);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SERVICE_ROLE_KEY") ?? "",
    );
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authorization } } },
    );

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();
    if (authError || !user) return jsonResponse({ error: "Unauthorized" }, 401);

    const { yapId } = await req.json();
    if (!yapId || typeof yapId !== "string") {
      return jsonResponse({ error: "Missing yapId" }, 400);
    }

    const { data: yap, error: yapError } = await admin
      .from("yaps")
      .select("id, user_id, is_deleted")
      .eq("id", yapId)
      .maybeSingle();

    if (yapError) throw yapError;
    if (!yap) return jsonResponse({ error: "Yap not found" }, 404);
    if (yap.user_id !== user.id) return jsonResponse({ error: "Forbidden" }, 403);
    if (yap.is_deleted) return jsonResponse({ success: true, alreadyDeleted: true });

    const { error: updateError } = await admin
      .from("yaps")
      .update({ is_deleted: true, deleted_at: new Date().toISOString() })
      .eq("id", yapId)
      .eq("user_id", user.id);
    if (updateError) throw updateError;

    return jsonResponse({ success: true });
  } catch (error) {
    console.error("delete-yap failed", error);
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Delete failed" },
      500,
    );
  }
});
