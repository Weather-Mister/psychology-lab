import { db } from "hatchable";

export const access = "public";
export const methods = ["POST", "OPTIONS"];

function applyCors(req, res) {
  const origin = String(req.headers?.origin || req.headers?.Origin || "");
  const allowed = origin === "https://weather-mister.github.io" || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
  if (allowed) res.setHeader("Access-Control-Allow-Origin", origin);
  res.setHeader("Vary", "Origin");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

function normalize(value) {
  return String(value || "").trim().toLowerCase();
}
function parseState(text) {
  try {
    const parsed = JSON.parse(String(text || "{}"));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
  } catch { return {}; }
}

export default async function (req, res) {
  applyCors(req, res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  const username = normalize(req.body?.username);
  const state = req.body?.state;
  const expectedRevision = Number(req.body?.expectedRevision);

  if (!/^[a-z0-9_]{2,32}$/.test(username)) {
    return res.status(400).json({ error: "Invalid username." });
  }
  if (!state || typeof state !== "object" || Array.isArray(state)) {
    return res.status(400).json({ error: "Invalid profile state." });
  }
  if (!Number.isInteger(expectedRevision) || expectedRevision < 0) {
    return res.status(400).json({ error: "Invalid revision." });
  }

  const encoded = JSON.stringify(state);
  if (encoded.length > 1000000) {
    return res.status(413).json({ error: "Profile state is too large." });
  }

  const updated = await db.query(
    "UPDATE psychology_profiles SET state_text = $1, revision = revision + 1, updated_at = NOW() WHERE username = $2 AND revision = $3 RETURNING state_text, revision",
    [encoded, username, expectedRevision]
  );

  if (updated.rows.length) {
    const row = updated.rows[0];
    return res.json({ state: parseState(row.state_text), revision: Number(row.revision) });
  }

  const current = await db.query(
    "SELECT state_text, revision FROM psychology_profiles WHERE username = $1",
    [username]
  );

  if (!current.rows.length && expectedRevision === 0) {
    const inserted = await db.query(
      "INSERT INTO psychology_profiles (username, state_text, revision) VALUES ($1, $2, 1) ON CONFLICT (username) DO NOTHING RETURNING state_text, revision",
      [username, encoded]
    );
    if (inserted.rows.length) {
      return res.json({ state: parseState(inserted.rows[0].state_text), revision: Number(inserted.rows[0].revision) });
    }
  }

  const latest = current.rows[0] || (await db.query(
    "SELECT state_text, revision FROM psychology_profiles WHERE username = $1",
    [username]
  )).rows[0];

  return res.status(409).json({
    error: "Profile changed elsewhere.",
    state: parseState(latest?.state_text),
    revision: Number(latest?.revision || 0)
  });
}