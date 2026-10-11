// The brain: talks to Groq, remembers recent chat per channel, and splits long
// answers so they fit Discord's 2000 character limit. No Discord code in here.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

// ---------- load .env ----------
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
  // no .env file; use real environment variables
}

export const AI_NAME = process.env.AI_NAME || "DarkGPT";
const API_BASE = (process.env.GROQ_BASE_URL || "https://api.groq.com/openai/v1").replace(/\/$/, "");
const API_KEY = process.env.GROQ_API_KEY;
export let MODEL = process.env.MODEL || "llama-3.3-70b-versatile";

const SYSTEM_PROMPT = `You are ${AI_NAME}, a sharp, straight-talking AI assistant with a sleek, dark personality, chatting in Discord.
Keep answers short and punchy: usually under 1500 characters unless the user asks for something long.
Use Discord markdown (bold, lists, fenced code blocks for code). Never use markdown headers.
You are good at Roblox game development (Luau), Minecraft, coding, and everyday questions.
In group chats, each user message starts with the person's name and a colon. Reply to the person who just spoke.
If you are unsure of something, say so instead of guessing.`;

// ---------- pick a model that really exists for this account ----------
const PREFERRED = ["llama-3.3-70b-versatile", "llama-3.1-70b-versatile", "openai/gpt-oss-120b", "llama-3.1-8b-instant"];

export async function resolveModel() {
  try {
    const res = await fetch(`${API_BASE}/models`, {
      headers: { Authorization: `Bearer ${API_KEY}` },
      signal: AbortSignal.timeout(8000),
    });
    if (res.status === 401) return "bad-key";
    if (!res.ok) return "ok";
    const ids = ((await res.json()).data || []).map((m) => m.id);
    if (ids.includes(MODEL)) return "ok";
    const skip = /whisper|guard|tts|playai|distil-whisper|embed/i;
    const pick = PREFERRED.find((id) => ids.includes(id)) || ids.find((id) => !skip.test(id));
    if (pick) {
      console.log(`Model "${MODEL}" is not available, using "${pick}" instead.`);
      MODEL = pick;
    }
    return "ok";
  } catch {
    return "offline";
  }
}

// ---------- memory: the last few messages in each channel ----------
const MEMORY_TURNS = 12;
const MAX_CHANNELS = 500;
const memory = new Map();

export function resetMemory(channelId) {
  memory.delete(channelId);
}

function remember(channelId, role, content) {
  const list = memory.get(channelId) || [];
  list.push({ role, content });
  while (list.length > MEMORY_TURNS) list.shift();
  memory.delete(channelId);          // re-insert so the busiest channels stay at the end
  memory.set(channelId, list);
  while (memory.size > MAX_CHANNELS) memory.delete(memory.keys().next().value);
  return list;
}

// ---------- split long text into Discord-sized pieces ----------
export function splitMessage(text, limit = 1900) {
  const out = [];
  let current = "";
  let fence = null;                       // the opening fence line while inside a code block
  const push = () => {
    if (!current.trim()) { current = ""; return; }
    if (fence) current += "\n```";        // close the block so this piece renders correctly
    out.push(current);
    current = fence ? fence : "";         // reopen it on the next piece
  };
  for (const rawLine of String(text).split("\n")) {
    let line = rawLine;
    while (line.length > limit - 10) {    // a single very long line
      if (current) push();
      out.push(line.slice(0, limit - 10));
      line = line.slice(limit - 10);
    }
    const add = (current ? "\n" : "") + line;
    if (current.length + add.length + (fence ? 4 : 0) > limit) push();
    current += (current ? "\n" : "") + line;
    if (line.trim().startsWith("```")) fence = fence ? null : line.trim();
  }
  if (current.trim()) out.push(current);
  return out.length ? out : ["..."];
}

// ---------- ask Groq ----------
function friendlyError(status, bodyText) {
  let detail = "";
  try { detail = JSON.parse(bodyText).error?.message || ""; } catch { detail = String(bodyText || "").slice(0, 160); }
  if (status === 401) return "My Groq key was rejected. The bot owner needs to check GROQ_API_KEY.";
  if (status === 429) return "I've hit my free limit for now. Try again in a minute.";
  if (status === 404 || /model/i.test(detail)) return "My AI model isn't available right now. The bot owner needs to check MODEL.";
  if (status >= 500) return "My AI provider is having trouble. Try again in a moment.";
  return "Something went wrong while thinking. Try again.";
}

// Returns an array of message chunks ready to send.
export async function answer({ channelId, userName, text, group = true }) {
  const clean = String(text || "").trim().slice(0, 1500);
  if (!clean) return ["Say something and I'll answer."];

  const list = remember(channelId, "user", group ? `${userName}: ${clean}` : clean);
  let reply;
  try {
    const res = await fetch(`${API_BASE}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: MODEL,
        messages: [{ role: "system", content: SYSTEM_PROMPT }, ...list],
        temperature: 0.7,
        max_tokens: 1024,
      }),
      signal: AbortSignal.timeout(45_000),
    });
    if (!res.ok) {
      list.pop();                          // do not remember a question that never got answered
      return [friendlyError(res.status, await res.text())];
    }
    reply = ((await res.json()).choices?.[0]?.message?.content || "").trim();
  } catch (err) {
    list.pop();
    return [err && err.name === "TimeoutError" ? "That took too long. Try again." : "I couldn't reach my AI provider. Try again in a moment."];
  }
  if (!reply) { list.pop(); return ["I didn't come up with anything. Try asking another way."]; }

  remember(channelId, "assistant", reply);
  return splitMessage(reply);
}
