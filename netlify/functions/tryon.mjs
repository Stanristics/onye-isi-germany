// AI hair try-on. Keys stay on the server. Requires a logged-in Onye Isi user (verified with Supabase).
// Env vars (Netlify > Site configuration > Environment variables), set at least one provider:
//   GEMINI_API_KEY (+ optional GEMINI_MODEL, default gemini-2.5-flash-image)
//   BFL_API_KEY    (+ optional BFL_BASE, default https://api.eu.bfl.ai ; BFL_PATH, default /v1/flux-2-pro)
//   TRYON_PROVIDER = "gemini" or "flux" (default provider when both are configured)

const SB_URL = "https://hregrxngtmekccxzxotz.supabase.co";
const SB_KEY = "sb_publishable_U75nqHazrNZBGi6VII0rkg_FNDp0jx2"; // public by design
const env = k => globalThis.Netlify?.env?.get(k) ?? process.env[k];

const STYLES = {
  "knotless-braids": "medium-length knotless box braids",
  "box-braids": "classic box braids",
  "cornrows": "neat straight-back cornrows",
  "locs": "shoulder-length locs",
  "twist-out": "a defined natural twist-out on natural hair",
  "afro": "a full rounded natural afro",
  "bantu-knots": "Bantu knots",
  "silk-press": "sleek, silk-pressed straight hair",
  "fade": "a clean low fade haircut with a sharp line-up"
};
const COLORS = { black: "natural black", brown: "dark brown", honey: "honey blonde", burgundy: "burgundy", copper: "copper" };

const MAX_B64 = 3_000_000;                 // ~2.2 MB image
const WINDOW_MS = 10 * 60 * 1000, PER_USER = 6, DAILY_CAP = 150;
const hits = new Map(); let day = new Date().toDateString(), dayCount = 0;  // best-effort, per function instance

const json = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { "Content-Type": "application/json" } });

async function verifyUser(req) {
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const r = await fetch(`${SB_URL}/auth/v1/user`, { headers: { apikey: SB_KEY, Authorization: `Bearer ${token}` } });
  return r.ok ? (await r.json())?.id || null : null;
}
function limited(uid) {
  const now = Date.now(), recent = (hits.get(uid) || []).filter(t => now - t < WINDOW_MS);
  if (new Date().toDateString() !== day) { day = new Date().toDateString(); dayCount = 0; }
  if (recent.length >= PER_USER || dayCount >= DAILY_CAP) return true;
  recent.push(now); hits.set(uid, recent); dayCount++; if (hits.size > 5000) hits.clear();
  return false;
}
// With TRYON_DEBUG=1 the real provider error is shown on the page. Turn it off again after testing.
const providerFail = msg => json({ error: "provider_error", ...(env("TRYON_DEBUG") === "1" ? { detail: String(msg).slice(0, 300) } : {}) }, 502);
const isBfl = u => { try { const x = new URL(u); return x.protocol === "https:" && /(^|\.)bfl\.ai$/.test(x.hostname); } catch { return false; } };

async function gemini(prompt, mime, b64) {
  const model = env("GEMINI_MODEL") || "gemini-2.5-flash-image";
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
    method: "POST", headers: { "x-goog-api-key": env("GEMINI_API_KEY"), "Content-Type": "application/json" },
    body: JSON.stringify({ contents: [{ parts: [{ text: prompt }, { inline_data: { mime_type: mime, data: b64 } }] }],
      generationConfig: { responseModalities: ["TEXT", "IMAGE"] } })
  });
  if (!r.ok) { const t = (await r.text()).slice(0, 300); console.error("Gemini", r.status, t); return providerFail(`Gemini ${r.status}: ${t}`); }
  const parts = (await r.json()).candidates?.[0]?.content?.parts || [];
  const inl = parts.map(p => p.inlineData || p.inline_data).find(Boolean);
  if (!inl) return json({ error: "moderated", ...(env("TRYON_DEBUG") === "1" ? { detail: "Gemini returned no image: " + (parts.find(p => p.text)?.text || "").slice(0, 200) } : {}) }, 422);
  return json({ image: `data:${inl.mimeType || inl.mime_type || "image/png"};base64,${inl.data}` });
}
async function fluxStart(prompt, b64) {
  const r = await fetch((env("BFL_BASE") || "https://api.eu.bfl.ai") + (env("BFL_PATH") || "/v1/flux-2-pro"), {
    method: "POST", headers: { "x-key": env("BFL_API_KEY"), "Content-Type": "application/json" },
    body: JSON.stringify({ prompt, input_image: b64 })
  });
  if (!r.ok) { const t = (await r.text()).slice(0, 300); console.error("BFL", r.status, t); return providerFail(`FLUX ${r.status}: ${t}`); }
  const d = await r.json();
  return isBfl(d.polling_url) ? json({ job: d.polling_url }) : providerFail("FLUX returned no polling URL");
}
async function fluxPoll(url) {
  if (!isBfl(url)) return json({ error: "bad_request" }, 400);
  const r = await fetch(url, { headers: { "x-key": env("BFL_API_KEY") } });
  if (!r.ok) return json({ error: "provider_error" }, 502);
  const d = await r.json();
  if (d.status === "Ready") {
    if (!isBfl(d.result?.sample)) return json({ error: "provider_error" }, 502);
    const img = await fetch(d.result.sample);
    if (!img.ok) return json({ error: "provider_error" }, 502);
    return json({ image: `data:${img.headers.get("content-type") || "image/png"};base64,${Buffer.from(await img.arrayBuffer()).toString("base64")}` });
  }
  if (/Moderated/.test(d.status || "")) return json({ error: "moderated" }, 422);
  if (d.status === "Error" || d.status === "Task not found") return providerFail("FLUX status: " + d.status);
  return json({ pending: true });
}

export default async (req) => {
  const allowed = env("ALLOWED_ORIGIN"), origin = req.headers.get("origin");
  if (allowed && origin && origin !== allowed) return json({ error: "forbidden" }, 403);
  const available = [env("GEMINI_API_KEY") && "gemini", env("BFL_API_KEY") && "flux"].filter(Boolean);
  if (!available.length) return json({ error: "not_configured" }, 503);
  const uid = await verifyUser(req);
  if (!uid) return json({ error: "login_required" }, 401);

  if (req.method === "GET") {                       // poll a FLUX job
    if (!env("BFL_API_KEY")) return json({ error: "bad_request" }, 400);
    return fluxPoll(new URL(req.url).searchParams.get("job") || "");
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);

  let body; try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
  const m = /^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/.exec(body?.image || "");
  if (!m || m[2].length > MAX_B64 || !STYLES[body.style] || (body.color && !COLORS[body.color])) return json({ error: "bad_request" }, 400);
  if (limited(uid)) return json({ error: "rate_limited" }, 429);

  const provider = available.includes(body.provider) ? body.provider
    : available.includes(env("TRYON_PROVIDER")) ? env("TRYON_PROVIDER") : available[0];
  const prompt = `Edit this photo: change only the person's hairstyle to ${STYLES[body.style]}` +
    (body.color ? `, in ${COLORS[body.color]} hair colour` : "") +
    `. Keep the face, facial features, skin tone, expression, clothing, pose, lighting and background exactly the same. Photorealistic result.`;
  try { return provider === "gemini" ? await gemini(prompt, m[1], m[2]) : await fluxStart(prompt, m[2]); }
  catch (e) { console.error(e); return providerFail(e.message); }
};

export const config = { path: "/api/tryon" };
