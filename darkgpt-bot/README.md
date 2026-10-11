# DarkGPT for Discord

A Discord bot powered by DarkGPT (Groq). Use `/ask`, or just @mention it. It also answers in DMs.

- `/ask prompt` : ask anything
- `@DarkGPT your question` : same thing, no slash needed
- `/reset` : make it forget the conversation in this channel
- `/about` : info

It remembers the last 12 messages in each channel and knows who is talking.

## Set up (about 5 minutes)

**1. Make the bot on Discord**
1. Go to https://discord.com/developers/applications and click **New Application**. Name it `DarkGPT`.
2. Open the **Bot** tab on the left.
3. Click **Reset Token**, then **Copy**. This is your bot token.
4. You do not need to turn on any "Privileged Gateway Intents".

**2. Put your keys in `.env`**

Open the `.env` file in this folder with Notepad and fill in:
```
DISCORD_TOKEN=the-token-you-just-copied
GROQ_API_KEY=gsk_your_key_here
```

**3. Run it**

Double-click `start.bat`. The first time it installs what it needs, then the bot starts and prints an
**invite link**. Open that link, choose your server, and click Authorize.

**4. Use it**

In your server, type `/ask` or mention `@DarkGPT`.

## Good to know

- The bot is only online while `start.bat` is running on your PC. Close the window and it goes offline.
- Optional: add `GUILD_ID=your-server-id` to `.env` to make slash commands appear instantly.
  (Discord settings, Advanced, turn on Developer Mode. Then right-click your server and Copy Server ID.)
- Change the name or model in `.env` with `AI_NAME` and `MODEL`.
- To change the personality, edit `SYSTEM_PROMPT` near the top of `ai.js`.
- Run `npm test` to check the AI logic without Discord.

## Safety

- Your bot token is like a password. Never share it or upload `.env`. If it leaks, press Reset Token again.
- The bot can never ping @everyone, roles or people. Each user is limited to one message every 4 seconds.
- Groq's free plan has usage limits. If the bot says it hit its limit, wait a minute.

## Files

- `bot.js` : the Discord part (commands, mentions, DMs)
- `ai.js` : the AI part (Groq, memory, splitting long answers)
- `test.js` : self-test
