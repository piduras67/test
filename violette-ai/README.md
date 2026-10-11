# Violette AI

A chat assistant page for Violette Hub, powered by Claude. The chat page talks to a small Node
server, and the server talks to Claude. Your API key stays on the server and never reaches the browser.

## Set up (Windows)

1. Install Node.js (LTS) from nodejs.org if you do not have it.
2. Get an API key at https://console.anthropic.com/ (API usage is billed separately from a claude.ai plan,
   so add a few dollars of credit there).
3. In this folder, copy `.env.example` to a new file named `.env` and put your key in it:
   ```
   ANTHROPIC_API_KEY=sk-ant-your-key-here
   ```
4. Open a terminal in this folder and run:
   ```
   npm install
   npm start
   ```
   If PowerShell blocks `npm`, run `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` once,
   or use the normal Command Prompt (cmd) instead.
5. Open http://localhost:3000

## Settings (in `.env`)

| Setting | Default | What it does |
| --- | --- | --- |
| `MODEL` | `claude-opus-5-5` | Which Claude model answers. `claude-haiku-5-5` is much cheaper and faster. |
| `EFFORT` | `low` | How hard the model thinks: `low`, `medium` or `high`. Higher is smarter but slower and costs more. |
| `AI_NAME` | `Violette` | The assistant's name. |
| `PORT` | `3000` | Which port the page runs on. |
| `HOST` | `127.0.0.1` | Keep this so only your own computer can open it. |

To change the assistant's personality, edit `SYSTEM_PROMPT` near the top of `server.js`.

## Safety

- Never share or upload your `.env` file. It is already listed in `.gitignore`.
- Do not put this on the public internet as it is. Anyone who can open the page can spend your credit.
  The server limits each visitor to 20 messages a minute, but it has no login.
- Chats are saved only in your own browser. "New chat" clears them.

## Files

- `server.js`: the server (API key, streaming, limits, error messages)
- `public/index.html`: the chat page
