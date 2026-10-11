// DarkGPT for Discord. Slash commands: /ask, /reset, /about. Also answers when you @mention it, and in DMs.

import {
  Client,
  Events,
  GatewayIntentBits,
  Partials,
  ChannelType,
  ApplicationCommandOptionType,
  MessageFlags,
} from "discord.js";
import { AI_NAME, MODEL, answer, resetMemory, resolveModel } from "./ai.js";

const TOKEN = process.env.DISCORD_TOKEN;
if (!TOKEN || TOKEN.includes("your-discord")) {
  console.error("\nNo Discord token found.");
  console.error('Put it in the ".env" file next to bot.js:  DISCORD_TOKEN=your-token');
  console.error("See README.md for how to create the bot and get the token.\n");
  process.exit(1);
}
if (!process.env.GROQ_API_KEY || process.env.GROQ_API_KEY.includes("your_key")) {
  console.error("\nNo Groq key found. Put it in the .env file:  GROQ_API_KEY=gsk_...\n");
  process.exit(1);
}

const keyStatus = await resolveModel();
if (keyStatus === "bad-key") {
  console.error("Groq rejected the API key. Check GROQ_API_KEY in your .env file.\n");
  process.exit(1);
}

const client = new Client({
  // Only non-privileged intents are needed: bots can read messages that mention them,
  // and every message in their DMs, without the "Message Content" switch.
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, GatewayIntentBits.DirectMessages],
  partials: [Partials.Channel],
});

const NO_PINGS = { parse: [] };   // the bot can never ping @everyone, roles or users
const COOLDOWN_MS = 4000;
const lastUse = new Map();

function onCooldown(userId) {
  const now = Date.now();
  const last = lastUse.get(userId) || 0;
  if (now - last < COOLDOWN_MS) return true;
  lastUse.set(userId, now);
  if (lastUse.size > 5000) lastUse.clear();
  return false;
}

const COMMANDS = [
  {
    name: "ask",
    description: `Ask ${AI_NAME} anything`,
    options: [{ type: ApplicationCommandOptionType.String, name: "prompt", description: "What do you want to ask?", required: true, max_length: 1500 }],
  },
  { name: "reset", description: `Make ${AI_NAME} forget this channel's conversation` },
  { name: "about", description: `About ${AI_NAME}` },
];

client.once(Events.ClientReady, async (c) => {
  try {
    if (process.env.GUILD_ID) {
      const guild = await c.guilds.fetch(process.env.GUILD_ID);
      await guild.commands.set(COMMANDS);       // shows up instantly in that server
    } else {
      await c.application.commands.set(COMMANDS);
    }
  } catch (err) {
    console.error("Could not register slash commands:", err.message);
  }
  const invite = `https://discord.com/oauth2/authorize?client_id=${c.user.id}&scope=bot%20applications.commands&permissions=68608`;
  console.log(`\n${AI_NAME} is online as ${c.user.tag}`);
  console.log(`Model: ${MODEL}`);
  console.log(`\nInvite link (open it to add the bot to your server):\n${invite}\n`);
});

// ---------- slash commands ----------
client.on(Events.InteractionCreate, async (interaction) => {
  if (!interaction.isChatInputCommand()) return;

  if (interaction.commandName === "about") {
    await interaction.reply({
      content: `**${AI_NAME}**: a sharp, straight-talking AI. Use \`/ask\`, or just @mention me. \`/reset\` clears my memory of this channel.\nModel: \`${MODEL}\``,
      allowedMentions: NO_PINGS,
    });
    return;
  }

  if (interaction.commandName === "reset") {
    resetMemory(interaction.channelId);
    await interaction.reply({ content: "Memory cleared for this channel.", allowedMentions: NO_PINGS });
    return;
  }

  if (interaction.commandName === "ask") {
    if (onCooldown(interaction.user.id)) {
      await interaction.reply({ content: "Easy there. Give me a few seconds.", flags: MessageFlags.Ephemeral });
      return;
    }
    await interaction.deferReply();
    const chunks = await answer({
      channelId: interaction.channelId || interaction.user.id,
      userName: interaction.member?.displayName || interaction.user.username,
      text: interaction.options.getString("prompt", true),
      group: interaction.inGuild(),
    });
    await interaction.editReply({ content: chunks[0], allowedMentions: NO_PINGS });
    for (const extra of chunks.slice(1)) {
      await interaction.followUp({ content: extra, allowedMentions: NO_PINGS });
    }
  }
});

// ---------- @mentions and DMs ----------
client.on(Events.MessageCreate, async (message) => {
  if (message.author.bot) return;
  const isDM = message.channel.type === ChannelType.DM;
  const mentioned = message.mentions.has(client.user, { ignoreEveryone: true, ignoreRoles: true });
  if (!isDM && !mentioned) return;

  if (onCooldown(message.author.id)) return;

  const text = message.content.replace(new RegExp(`<@!?${client.user.id}>`, "g"), "").trim();
  try { await message.channel.sendTyping(); } catch {}

  const chunks = await answer({
    channelId: message.channelId,
    userName: message.member?.displayName || message.author.username,
    text,
    group: !isDM,
  });
  await message.reply({ content: chunks[0], allowedMentions: { parse: [], repliedUser: false } });
  for (const extra of chunks.slice(1)) {
    await message.channel.send({ content: extra, allowedMentions: NO_PINGS });
  }
});

client.on(Events.Error, (err) => console.error("Discord error:", err.message));
process.on("unhandledRejection", (err) => console.error("Unhandled error:", err && err.message ? err.message : err));

client.login(TOKEN).catch((err) => {
  console.error("\nCould not log in to Discord:", err.message);
  console.error("Check DISCORD_TOKEN in your .env file (use the Bot token, not the client secret).\n");
  process.exit(1);
});
