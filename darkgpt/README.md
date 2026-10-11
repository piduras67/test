# DarkGPT

A chat assistant page powered by Groq. The page talks to a small Node server, and the server talks to
Groq. Your API key stays on the server and never reaches the browser. No packages to install.

## Run it (Windows)

1. Install Node.js (LTS) from nodejs.org if you do not have it.
2. Make sure a file named `.env` sits next to `server.js` and contains your key:
   ```
   GROQ_API_KEY=gsk_your_key_here
   ```
   (Get a free key at https://console.groq.com/keys. `.env.example` shows the format.)
3. Open a terminal in this folder and run:
   ```
   node server.js
   ```
4. Open http://localhost:3000

## Settings (in `.env`)

| Setting | Default | What it does |
| --- | --- | --- |
| `MODEL` | `llama-3.3-70b-versatile` | Which Groq model answers. If it is not available, the server picks one that is. |
| `AI_NAME` | `DarkGPT` | The assistant's name. |
| `PORT` | `3000` | Which port the page runs on. |
| `HOST` | `127.0.0.1` | Keep this so only your own computer can open it. |

To change the personality, edit `SYSTEM_PROMPT` near the top of `server.js`.

## Safety

- Never share or upload your `.env` file. It is listed in `.gitignore`.
- Do not put this on the public internet as it is. Anyone who can open the page can use your key.
  The server limits each visitor to 20 messages a minute, but it has no login.
- Groq's free plan has its own usage limits. If you hit them, wait a minute and try again.
- Chats are saved only in your own browser. "New chat" clears them.

## Files

- `server.js`: the server (API key, streaming, limits, error messages)
- `public/index.html`: the chat page
