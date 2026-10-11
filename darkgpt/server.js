// DarkGPT: a tiny web server between your chat page and the Groq API.
// The API key lives only here, on the server, and never reaches the browser.
// No packages needed. Requires Node 18 or newer.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

// ---------- load .env (so Windows users do not need to set variables by hand) ----------
try {
  const raw = fs.readFileSync(path.join(here, ".env"), "utf8");
  for (const line of raw.split(/\r?\n/)) {
    if (line.trim().startsWith("#")) continue;
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (!m) continue;
    const value = m[2].replace(/^["']|["']$/g, "");
    if (process.env[m[1]] === undefined) process.env[m[1]] = value;
  }
} catch {
  // no .env file; fall back to real environment variables
}

const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || "127.0.0.1";
const AI_NAME = process.env.AI_NAME || "DarkGPT";
const API_BASE = (process.env.GROQ_BASE_URL || "https://api.groq.com/openai/v1").replace(/\/$/, "");
const API_KEY = process.env.GROQ_API_KEY;
let MODEL = process.env.MODEL || "llama-3.3-70b-versatile";

const SYSTEM_PROMPT = `You are ${AI_NAME}, a sharp, straight-talking AI assistant with a sleek, dark personality.
You are helpful, clear and concise. Prefer short paragraphs, and use fenced code blocks for code.
You are good at Roblox game development (Luau), Minecraft, web development, and everyday questions.
If you are unsure of something, say so instead of guessing.`;

if (!API_KEY) {
  console.error("\nNo API key found.");
  console.error('Create a file named ".env" next to server.js containing:');
  console.error("  GROQ_API_KEY=gsk_your_key_here\n");
  console.error("Get a free key at https://console.groq.com/keys\n");
  process.exit(1);
}

// ---------- pick a model that really exists for this account ----------
const PREFERRED = [
  "llama-3.3-70b-versatile",
  "llama-3.1-70b-versatile",
  "openai/gpt-oss-120b",
  "llama-3.1-8b-instant",
];
async function resolveModel() {
  try {
    const res = await fetch(`${API_BASE}/models`, {
      headers: { Authorization: `Bearer ${API_KEY}` },
      signal: AbortSignal.timeout(8000),
    });
    if (res.status === 401) {
      console.error("Groq rejected the API key. Check GROQ_API_KEY in your .env file.\n");
      return;
    }
    if (!res.ok) return;
    const ids = ((await res.json()).data || []).map((m) => m.id);
    if (ids.includes(MODEL)) return;
    const skip = /whisper|guard|tts|playai|distil-whisper|embed/i;
    const pick = PREFERRED.find((id) => ids.includes(id)) || ids.find((id) => !skip.test(id));
    if (pick) {
      console.log(`Model "${MODEL}" is not available, using "${pick}" instead.`);
      MODEL = pick;
    }
  } catch {
    // offline at startup: keep the configured model
  }
}

// ---------- limits that protect your quota ----------
const MAX_BODY_BYTES = 200_000;
const MAX_MESSAGES = 40;
const MAX_CHARS_PER_MESSAGE = 8000;
const RATE_LIMIT = 20;            // requests per minute per visitor
const hits = new Map();

function rateLimited(ip) {
  const now = Date.now();
  const recent = (hits.get(ip) || []).filter((t) => now - t < 60_000);
  recent.push(now);
  hits.set(ip, recent);
  return recent.length > RATE_LIMIT;
}
setInterval(() => {
  const now = Date.now();
  for (const [ip, list] of hits) {
    if (!list.some((t) => now - t < 60_000)) hits.delete(ip);
  }
}, 60_000).unref();

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (c) => {
      size += c.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error("Request too large"), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function cleanMessages(input) {
  if (!Array.isArray(input) || input.length === 0) return null;
  const msgs = input.slice(-MAX_MESSAGES).map((m) => ({
    role: m && m.role === "assistant" ? "assistant" : "user",
    content: String((m && m.content) ?? "").slice(0, MAX_CHARS_PER_MESSAGE),
  }));
  const nonEmpty = msgs.filter((m) => m.content.trim() !== "");
  while (nonEmpty.length && nonEmpty[0].role !== "user") nonEmpty.shift();
  if (!nonEmpty.length || nonEmpty[nonEmpty.length - 1].role !== "user") return null;
  return nonEmpty;
}

function friendlyError(status, bodyText) {
  let detail = "";
  try { detail = JSON.parse(bodyText).error?.message || ""; } catch { detail = String(bodyText || "").slice(0, 200); }
  if (status === 401) return "Groq rejected the API key. Check GROQ_API_KEY in your .env file.";
  if (status === 429) return "Groq's free limit was hit. Wait a minute and try again.";
  if (status === 404 || /model/i.test(detail)) return `Groq says the model "${MODEL}" is not available. Set MODEL in your .env to one from console.groq.com.`;
  if (status >= 500) return "Groq is having trouble right now. Try again in a moment.";
  return detail ? `Groq error: ${detail}` : `Groq returned an error (${status}).`;
}

// ---------- the chat endpoint (streams the reply as server-sent events) ----------
async function handleChat(req, res) {
  const ip = req.socket.remoteAddress || "unknown";
  if (rateLimited(ip)) {
    res.writeHead(429, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Slow down a little. Try again in a minute." }));
    return;
  }

  let messages;
  try {
    const body = JSON.parse(await readBody(req));
    messages = cleanMessages(body.messages);
  } catch (err) {
    res.writeHead(err.status || 400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: err.status === 413 ? "That message is too large." : "Bad request." }));
    return;
  }
  if (!messages) {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Send at least one message." }));
    return;
  }

  res.writeHead(200, {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-transform",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  });
  const send = (obj) => res.write(`data: ${JSON.stringify(obj)}\n\n`);

  const abort = new AbortController();
  res.on("close", () => abort.abort());

  try {
    const upstream = await fetch(`${API_BASE}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: MODEL,
        messages: [{ role: "system", content: SYSTEM_PROMPT }, ...messages],
        stream: true,
        temperature: 0.7,
        max_tokens: 4096,
      }),
      signal: abort.signal,
    });

    if (!upstream.ok) {
      send({ error: friendlyError(upstream.status, await upstream.text()) });
      return;
    }

    const decoder = new TextDecoder();
    let buf = "";
    let finish = null;
    for await (const chunk of upstream.body) {
      buf += decoder.decode(chunk, { stream: true });
      let nl;
      while ((nl = buf.indexOf("\n")) !== -1) {
        const line = buf.slice(0, nl).trim();
        buf = buf.slice(nl + 1);
        if (!line.startsWith("data:")) continue;
        const payload = line.slice(5).trim();
        if (payload === "[DONE]") continue;
        let json;
        try { json = JSON.parse(payload); } catch { continue; }
        if (json.error) { send({ error: friendlyError(500, JSON.stringify(json)) }); continue; }
        const choice = json.choices && json.choices[0];
        if (!choice) continue;
        if (choice.delta && choice.delta.content) send({ text: choice.delta.content });
        if (choice.finish_reason) finish = choice.finish_reason;
      }
    }
    send({ done: true, stop_reason: finish });
  } catch (err) {
    if (err && err.name === "AbortError") return;
    console.error("chat error:", err && err.message);
    if (!res.writableEnded) send({ error: "Could not reach Groq. Check your internet connection." });
  } finally {
    if (!res.writableEnded) res.end();
  }
}

// ---------- tiny static server for the page ----------
const PAGE = path.join(here, "public", "index.html");

const server = http.createServer((req, res) => {
  const url = (req.url || "/").split("?")[0];

  if (req.method === "POST" && url === "/api/chat") {
    handleChat(req, res).catch((err) => {
      console.error(err);
      if (!res.headersSent) res.writeHead(500);
      res.end();
    });
    return;
  }

  if (req.method === "GET" && url === "/api/info") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ name: AI_NAME, model: MODEL }));
    return;
  }

  if (req.method === "GET" && (url === "/" || url === "/index.html")) {
    fs.readFile(PAGE, (err, data) => {
      if (err) {
        res.writeHead(500);
        res.end("Could not read the page.");
        return;
      }
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-cache" });
      res.end(data);
    });
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("Not found");
});

await resolveModel();
server.listen(PORT, HOST, () => {
  console.log(`\n${AI_NAME} is running at http://${HOST === "0.0.0.0" ? "localhost" : HOST}:${PORT}`);
  console.log(`Model: ${MODEL}\n`);
});
