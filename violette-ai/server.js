// Violette AI: a tiny web server that sits between your chat page and Claude.
// The API key lives only here, on the server, and never reaches the browser.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import Anthropic from "@anthropic-ai/sdk";

const here = path.dirname(fileURLToPath(import.meta.url));

// ---------- load .env (so Windows users do not need to set variables by hand) ----------
try {
  const raw = fs.readFileSync(path.join(here, ".env"), "utf8");
  for (const line of raw.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (!m || line.trim().startsWith("#")) continue;
    const value = m[2].replace(/^["']|["']$/g, "");
    if (process.env[m[1]] === undefined) process.env[m[1]] = value;
  }
} catch {
  // no .env file; fall back to real environment variables
}

const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || "127.0.0.1";
const MODEL = process.env.MODEL || "claude-opus-5-5";
const EFFORT = process.env.EFFORT || "low";
const AI_NAME = process.env.AI_NAME || "Violette";

const SYSTEM_PROMPT = `You are ${AI_NAME}, the built-in assistant of Violette Hub.
You are friendly, clear and concise. Prefer short paragraphs, and use fenced code blocks for code.
You are good at helping with Roblox game development (Luau), Minecraft, web development and everyday questions.
If you are unsure of something, say so instead of guessing.`;

if (!process.env.ANTHROPIC_API_KEY) {
  console.error("\nNo API key found.");
  console.error('Create a file named ".env" next to server.js containing:');
  console.error("  ANTHROPIC_API_KEY=sk-ant-your-key-here\n");
  console.error("Get a key at https://console.anthropic.com/ (API usage is billed separately from claude.ai plans).\n");
  process.exit(1);
}

const client = new Anthropic();

// ---------- limits that protect your credit ----------
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
  // drop empty turns, then make sure the conversation starts and ends with the user
  const nonEmpty = msgs.filter((m) => m.content.trim() !== "");
  while (nonEmpty.length && nonEmpty[0].role !== "user") nonEmpty.shift();
  if (!nonEmpty.length || nonEmpty[nonEmpty.length - 1].role !== "user") return null;
  // merge consecutive turns from the same role so the API accepts them
  const merged = [];
  for (const m of nonEmpty) {
    const last = merged[merged.length - 1];
    if (last && last.role === m.role) last.content += "\n\n" + m.content;
    else merged.push({ ...m });
  }
  return merged;
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

  let current = null;
  req.on("close", () => {
    if (current) current.abort();
  });

  async function run(useFallback) {
    const params = {
      model: MODEL,
      max_tokens: 16000,
      system: SYSTEM_PROMPT,
      output_config: { effort: EFFORT },
      messages,
    };
    if (useFallback) {
      // If Claude's safety systems decline a request, a fallback model can answer it instead.
      params.betas = ["server-side-fallback-2026-07-01"];
      params.fallbacks = "default";
    }
    const stream = useFallback ? client.beta.messages.stream(params) : client.messages.stream(params);
    current = stream;

    let sentAny = false;
    for await (const event of stream) {
      if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
        sentAny = true;
        send({ text: event.delta.text });
      }
    }
    const final = await stream.finalMessage();
    return { final, sentAny };
  }

  try {
    let result;
    try {
      result = await run(process.env.FALLBACKS !== "off");
    } catch (err) {
      // If the optional fallback feature is rejected, quietly retry without it.
      if (err instanceof Anthropic.BadRequestError && process.env.FALLBACKS !== "off") {
        result = await run(false);
      } else {
        throw err;
      }
    }
    if (result.final.stop_reason === "refusal") {
      send({ text: result.sentAny ? "\n\n" : "", notice: "I can't help with that one." });
    }
    send({ done: true, stop_reason: result.final.stop_reason });
  } catch (err) {
    let message = "Something went wrong talking to Claude.";
    if (err instanceof Anthropic.AuthenticationError) message = "The API key was rejected. Check ANTHROPIC_API_KEY in your .env file.";
    else if (err instanceof Anthropic.RateLimitError) message = "Claude is rate limited right now. Try again in a moment.";
    else if (err instanceof Anthropic.NotFoundError) message = `The model "${MODEL}" was not found for your account.`;
    else if (err instanceof Anthropic.APIConnectionError) message = "Could not reach the Claude API. Check your internet connection.";
    else if (err instanceof Anthropic.APIError && err.status === 400 && /credit|billing/i.test(String(err.message))) {
      message = "Your Anthropic account is out of credit. Add some at console.anthropic.com.";
    }
    console.error("chat error:", err && err.message);
    if (!res.writableEnded) send({ error: message });
  } finally {
    if (!res.writableEnded) res.end();
  }
}

// ---------- tiny static server for the page ----------
const PAGE = path.join(here, "public", "index.html");

const server = http.createServer(async (req, res) => {
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

server.listen(PORT, HOST, () => {
  console.log(`\n${AI_NAME} is running at http://${HOST === "0.0.0.0" ? "localhost" : HOST}:${PORT}`);
  console.log(`Model: ${MODEL}   Effort: ${EFFORT}\n`);
});
