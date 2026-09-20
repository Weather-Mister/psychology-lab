import { db } from "hatchable";

export const access = "public";
export const methods = ["POST", "OPTIONS"];

function applyCors(req, res) {
  const origin = String(req.headers?.origin || "");
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
  if (!/^[a-z0-9_]{2,32}$/.test(username)) {
    return res.status(400).json({ error: "Invalid username." });
  }

  let result = await db.query(
    "SELECT username, state_text, revision FROM psychology_profiles WHERE username = $1",
    [username]
  );

  if (!result.rows.length) {
    await db.query(
      "INSERT INTO psychology_profiles (username) VALUES ($1) ON CONFLICT (username) DO NOTHING",
      [username]
    );
    result = await db.query(
      "SELECT username, state_text, revision FROM psychology_profiles WHERE username = $1",
      [username]
    );
  }

  const row = result.rows[0];
  return res.json({ username: row.username, state: parseState(row.state_text), revision: Number(row.revision || 0) });
}