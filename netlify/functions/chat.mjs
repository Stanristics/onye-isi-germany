// Netlify Function: keeps the Groq API key on the server.
// Set GROQ_API_KEY in Netlify: Site configuration > Environment variables.
// Optional: GROQ_MODEL (default below) and ALLOWED_ORIGIN (e.g. https://your-site.netlify.app).

const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";
const MODEL = process.env.GROQ_MODEL || "openai/gpt-oss-120b";
const REASONING_EFFORT = process.env.GROQ_REASONING_EFFORT ?? "low"; // set to "" for non-gpt-oss models
const MAX_TOKENS = 1200;

const LIMITS = { messages: 12, content: 6000, system: 6000 };
const WINDOW_MS = 10 * 60 * 1000;
const MAX_REQUESTS_PER_WINDOW = 20;
const hits = new Map(); // best-effort per-IP limiter (resets when the function instance recycles)

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { "Content-Type": "application/json" } });

function rateLimited(ip) {
  const now = Date.now();
  const recent = (hits.get(ip) || []).filter(t => now - t < WINDOW_MS);
  recent.push(now);
  hits.set(ip, recent);
  if (hits.size > 5000) hits.clear();
  return recent.length > MAX_REQUESTS_PER_WINDOW;
}

export default async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const key = process.env.GROQ_API_KEY;
  if (!key) return json({ error: "Server is not configured" }, 500);

  const allowed = process.env.ALLOWED_ORIGIN;
  const origin = req.headers.get("origin");
  if (allowed && origin && origin !== allowed) return json({ error: "Forbidden" }, 403);

  const ip = req.headers.get("x-nf-client-connection-ip") ||
             (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || "unknown";
  if (rateLimited(ip)) return json({ error: "Too many requests" }, 429);

  let body;
  try { body = await req.json(); } catch { return json({ error: "Bad request" }, 400); }

  const { system, messages } = body || {};
  const validMsgs =
    Array.isArray(messages) && messages.length > 0 && messages.length <= LIMITS.messages &&
    messages.every(m => m && ["user", "assistant"].includes(m.role) &&
                        typeof m.content === "string" && m.content.length > 0 && m.content.length <= LIMITS.content);
  if (typeof system !== "string" || system.length > LIMITS.system || !validMsgs) {
    return json({ error: "Invalid request" }, 400);
  }

  const payload = {
    model: MODEL,
    temperature: 0.7,
    max_completion_tokens: MAX_TOKENS,
    messages: [{ role: "system", content: system }, ...messages.map(({ role, content }) => ({ role, content }))]
  };
  if (REASONING_EFFORT) payload.reasoning_effort = REASONING_EFFORT;

  let upstream;
  try {
    upstream = await fetch(GROQ_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify(payload)
    });
  } catch {
    return json({ error: "Upstream unreachable" }, 502);
  }

  if (!upstream.ok) {
    console.error("Groq error", upstream.status, (await upstream.text()).slice(0, 300));
    return json({ error: "Upstream error" }, upstream.status === 429 ? 429 : 502);
  }
  const data = await upstream.json();
  const reply = (data.choices?.[0]?.message?.content || "").trim();
  return json({ reply });
};

export const config = { path: "/api/chat" };
