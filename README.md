# OpenClaw + CashClaw + LiteLLM — Autonomous Income Stack

Self-hosted AI agent that runs 24/7, accepts freelance missions, delivers work via AI, and collects payment. Zero recurring costs — all LLM providers are free tier.

## What Gets Installed

| Component | Port | Purpose |
|-----------|------|---------|
| **LiteLLM** | 4000 (localhost) | Intelligent LLM router — 6 free providers, 28 model routes, automatic fallbacks |
| **OpenClaw** | 18789 (localhost) | AI agent on Telegram — responds to messages via LiteLLM |
| **CashClaw** | 3847 (localhost) | Autonomous freelancer — SEO audits, blog posts, Stripe payments, HYRVE marketplace |
| **Mission Control** | 3333 (localhost) | Dashboard — real-time agent monitoring |
| **PostgreSQL** | 5432 (localhost) | LiteLLM UI database |

All ports are localhost-only. Access via SSH tunnel.

## Server Requirements

- **OS:** Ubuntu 22.04 or 24.04
- **RAM:** 8GB minimum
- **CPU:** 2 vCPU
- **Disk:** 40GB SSD
- **Recommended:** Hetzner Cloud CX22 (~$4/month) — https://www.hetzner.com/cloud

## Quick Start

```bash
# 1. Clone this repo on your server
git clone https://github.com/YOUR_USER/deploy-kit.git
cd deploy-kit

# 2. Run install (creates /home/claude/.env on first run)
chmod +x install.sh
sudo ./install.sh

# 3. Fill your API keys in /home/claude/.env
sudo nano /home/claude/.env

# 4. Run install again
sudo ./install.sh

# 5. Access dashboards via SSH tunnel
ssh -p 2222 -L 4000:127.0.0.1:4000 -L 3333:127.0.0.1:3333 -L 3847:127.0.0.1:3847 root@YOUR_SERVER
```

Then open:
- **LiteLLM UI:** http://localhost:4000/ui (admin / admin123)
- **Mission Control:** http://localhost:3333
- **CashClaw:** http://localhost:3847

## Free API Keys (sign up)

| Provider | Free Limit | Sign Up |
|----------|-----------|---------|
| Cerebras | 1M tokens/day | https://cloud.cerebras.ai |
| Groq | 14,400 req/day | https://console.groq.com |
| Google Gemini | 1,500 req/day (Flash) | https://aistudio.google.com |
| OpenRouter | Free models | https://openrouter.ai |
| Mistral | 1B tokens/month | https://console.mistral.ai |
| SambaNova | Unlimited (Llama 405B) | https://cloud.sambanova.ai |

## LiteLLM Model Routes

| Route | Primary Provider | Fallback Chain | Best For |
|-------|-----------------|----------------|----------|
| `gpt-4o` | Kimi K2 (Groq) | Groq Llama → Gemini Flash → SambaNova → Cerebras | Default |
| `agent` | Kimi K2 (Groq) | Groq Llama → Cerebras | Agent loops |
| `fast` | Groq Llama 70B | Gemini Flash → Cerebras | Low latency |
| `complex` | Gemini Flash | Qwen 235B → DeepSeek R1 → GPT-OSS 120B | Deep reasoning |
| `coding` | Kimi K2 (Groq) | Qwen3 Coder → GPT-OSS 120B | Code generation |
| `reasoning` | DeepSeek R1 | Qwen 235B → Gemini Flash | Chain-of-thought |
| `volume` | Mistral Large | — | Bulk content |
| `power` | DeepSeek V3.2 | GPT-OSS 120B → Gemini Pro | Max capability |
| `content` | Groq Llama 70B | Mistral → Gemini Flash | Blog posts, copy |

## Telegram Bot Setup

1. Message @BotFather on Telegram → `/newbot`
2. Copy the bot token → paste in `.env` as `TELEGRAM_BOT_TOKEN`
3. Message your bot → it will show a pairing code
4. Approve: `openclaw pairing approve telegram CODE`

## CashClaw + HYRVE Setup

1. Sign up at https://hyrveai.com
2. Get API key → paste in `.env` as `HYRVE_API_KEY`
3. Run: `cashclaw hyrve claim YOUR_KEY`
4. Enable auto-accept: `cashclaw hyrve auto-accept on --max 500`

## Stripe Setup

1. Get restricted key from https://dashboard.stripe.com/apikeys
2. Paste in `.env` as `STRIPE_SECRET_KEY`
3. Run: `cashclaw config set stripe.secret_key YOUR_KEY`
4. Run: `cashclaw config set stripe.connected true`

## Security

- SSH: key-only auth, password disabled
- UFW: deny all incoming except SSH (port 2222)
- Fail2ban: active on SSH + nginx
- All dashboards: localhost-only, access via SSH tunnel
- LiteLLM: master key auth required
- Secrets: `/home/claude/.env` is `chmod 600`

## Daily Briefing

Telegram message at 07:00 CET with system status and earnings. Configured via cron.

## Architecture

```
Telegram → OpenClaw (18789) → LiteLLM (4000) → Free LLM Providers
                                                  ├── Cerebras
                                                  ├── Groq (Kimi K2, Llama 70B)
                                                  ├── Gemini (Flash, Pro)
                                                  ├── Mistral Large
                                                  ├── SambaNova (DeepSeek, Llama)
                                                  └── OpenRouter (free models)

CashClaw (3847) → HYRVE Marketplace → Stripe Payments
Mission Control (3333) → OpenClaw Gateway (real-time data)
```

## License

MIT
