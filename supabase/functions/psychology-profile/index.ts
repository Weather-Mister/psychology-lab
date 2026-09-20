import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
const secretKey = secretKeys.default || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const supabase = createClient(SUPABASE_URL, secretKey, {
  auth: { persistSession: false, autoRefreshToken: false }
});

const GITHUB_ORIGIN = "https://weather-mister.github.io";

function corsHeaders(req: Request) {
  const origin = req.headers.get("origin") || "";
  const allowed =
    origin === GITHUB_ORIGIN ||
    /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
  return {
    "Access-Control-Allow-Origin": allowed ? origin : GITHUB_ORIGIN,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    "Vary": "Origin",
  };
}

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

function normalize(value: unknown) {
  return String(value || "").trim().toLowerCase();
}

function parseState(text: unknown) {
  try {
    const parsed = JSON.parse(String(text || "{}"));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("", { status: 204, headers: corsHeaders(req) });
  }
  if (req.method !== "POST") {
    return json(req, { error: "Method not allowed." }, 405);
  }

  const origin = req.headers.get("origin") || "";
  if (
    origin &&
    origin !== GITHUB_ORIGIN &&
    !/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)
  ) {
    return json(req, { error: "Origin not allowed." }, 403);
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json(req, { error: "Invalid JSON." }, 400);
  }

  const action = String(body?.action || "");
  const username = normalize(body?.username);

  if (!/^[a-z0-9_]{2,32}$/.test(username)) {
    return json(req, { error: "Invalid username." }, 400);
  }

  if (action === "load") {
    const { data, error } = await supabase.rpc("psychology_profile_load", {
      p_username: username,
    });
    if (error) return json(req, { error: "Could not load profile." }, 500);

    const row = data?.[0];
    if (!row) return json(req, { error: "Could not load profile." }, 500);

    return json(req, {
      username: row.username,
      state: parseState(row.state_text),
      revision: Number(row.revision || 0),
    });
  }

  if (action === "save") {
    const state = body?.state;
    const expectedRevision = Number(body?.expectedRevision);

    if (!state || typeof state !== "object" || Array.isArray(state)) {
      return json(req, { error: "Invalid profile state." }, 400);
    }
    if (!Number.isInteger(expectedRevision) || expectedRevision < 0) {
      return json(req, { error: "Invalid revision." }, 400);
    }

    const encoded = JSON.stringify(state);
    if (encoded.length > 1000000) {
      return json(req, { error: "Profile state is too large." }, 413);
    }

    const { data, error } = await supabase.rpc("psychology_profile_save", {
      p_username: username,
      p_state_text: encoded,
      p_expected_revision: expectedRevision,
    });
    if (error) return json(req, { error: "Could not save profile." }, 500);

    const row = data?.[0];
    if (!row) return json(req, { error: "Could not save profile." }, 500);

    const response = {
      state: parseState(row.state_text),
      revision: Number(row.revision || 0),
    };

    if (row.ok) return json(req, response, 200);
    return json(req, { error: "Profile changed elsewhere.", ...response }, 409);
  }

  return json(req, { error: "Unknown action." }, 400);
});
