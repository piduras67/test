// Quick self-test for the AI logic (no Discord or internet needed).
// Run with:  npm test
import http from "node:http";
import assert from "node:assert/strict";

let mode = "ok";
let lastBody = null;
const mock = http.createServer((req, res) => {
  if (req.url === "/models") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ data: [{ id: "whisper-large-v3" }, { id: "llama-3.3-70b-versatile" }] }));
    return;
  }
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    lastBody = JSON.parse(body);
    if (mode === "429") { res.writeHead(429, { "content-type": "application/json" }); res.end('{"error":{"message":"rate"}}'); return; }
    if (mode === "long") {
      const long = "Here is code:\n```lua\n" + Array.from({ length: 150 }, (_, i) => `print("line number ${i} of the script")`).join("\n") + "\n```\nDone.";
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ choices: [{ message: { content: long } }] }));
      return;
    }
    const last = lastBody.messages.at(-1).content;
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ choices: [{ message: { content: `echo: ${last}` } }] }));
  });
}).listen(4030, "127.0.0.1");

process.env.GROQ_BASE_URL = "http://127.0.0.1:4030";
process.env.GROQ_API_KEY = "test-key";
process.env.MODEL = "retired-model";
const ai = await import("./ai.js");

let passed = 0;
const ok = (name) => { passed++; console.log("  ok  " + name); };

// model fallback
assert.equal(await ai.resolveModel(), "ok");
assert.equal(ai.MODEL, "llama-3.3-70b-versatile");
ok("picks a real model when the configured one is missing");

// splitting
const short = ai.splitMessage("hello world");
assert.deepEqual(short, ["hello world"]);
const big = ai.splitMessage("a".repeat(5000));
assert.ok(big.length >= 3 && big.every((c) => c.length <= 2000));
const para = ai.splitMessage(Array.from({ length: 200 }, (_, i) => `line ${i}`).join("\n"));
assert.ok(para.every((c) => c.length <= 2000) && para.join("\n").includes("line 199"));
ok("splits long text under 2000 characters");

const code = ai.splitMessage("Here is code:\n```lua\n" + Array.from({ length: 150 }, (_, i) => `print("line number ${i} of the script")`).join("\n") + "\n```\nDone.");
assert.ok(code.length > 1 && code.every((c) => c.length <= 2000));
for (const piece of code) assert.equal((piece.match(/```/g) || []).length % 2, 0, "every piece has balanced code fences");
ok("keeps code blocks balanced across pieces");

// conversation
let out = await ai.answer({ channelId: "c1", userName: "Sam", text: "hi there" });
assert.deepEqual(out, ["echo: Sam: hi there"]);
out = await ai.answer({ channelId: "c1", userName: "Lee", text: "and me" });
assert.deepEqual(lastBody.messages.map((m) => m.role), ["system", "user", "assistant", "user"]);
assert.equal(lastBody.messages.at(-1).content, "Lee: and me");
ok("remembers the channel and names who is talking");

out = await ai.answer({ channelId: "dm1", userName: "Sam", text: "private", group: false });
assert.equal(lastBody.messages.at(-1).content, "private");
ok("DMs skip the name prefix");

ai.resetMemory("c1");
await ai.answer({ channelId: "c1", userName: "Sam", text: "fresh" });
assert.equal(lastBody.messages.length, 2);
ok("reset forgets the channel");

out = await ai.answer({ channelId: "c2", userName: "Sam", text: "   " });
assert.match(out[0], /Say something/);
ok("empty message gets a hint");

// failures do not poison memory
mode = "429";
out = await ai.answer({ channelId: "c3", userName: "Sam", text: "first" });
assert.match(out[0], /free limit/);
mode = "ok";
await ai.answer({ channelId: "c3", userName: "Sam", text: "second" });
assert.equal(lastBody.messages.filter((m) => m.role === "user").length, 1);
ok("a failed request is not remembered, and the error is friendly");

mode = "long";
out = await ai.answer({ channelId: "c4", userName: "Sam", text: "write code" });
assert.ok(out.length > 1 && out.every((c) => c.length <= 2000));
ok("long AI answers come back as several valid messages");

mock.close();
console.log(`\nAll ${passed} checks passed.`);
