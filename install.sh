#!/usr/bin/env bash
set -euo pipefail

RED="\033[0;31m"; GREEN="\033[0;32m"; CYAN="\033[0;36m"; NC="\033[0m"
log() { printf "${CYAN}[install]${NC} %s\n" "$*"; }
ok()  { printf "${GREEN}[  ok  ]${NC} %s\n" "$*"; }
err() { printf "${RED}[error ]${NC} %s\n" "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="/home/claude/.env"

log "Preflight checks..."
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then err "Run as root"; exit 1; fi
if [[ ! -f "$ENV_FILE" ]]; then
  log "Creating $ENV_FILE from template..."
  id claude 2>/dev/null || useradd -m -s /bin/bash claude
  cp "$SCRIPT_DIR/configs/env.example" "$ENV_FILE"
  MASTER_KEY="sk-litellm-master-$(openssl rand -hex 16)"
  sed -i "s|LITELLM_MASTER_KEY=.*|LITELLM_MASTER_KEY=$MASTER_KEY|" "$ENV_FILE"
  chown claude:claude "$ENV_FILE" && chmod 600 "$ENV_FILE"
  err "Fill API keys in $ENV_FILE then re-run this script."
  exit 1
fi

source "$ENV_FILE"
if [[ -z "${CEREBRAS_API_KEY:-}" || -z "${GROQ_API_KEY:-}" || -z "${GEMINI_API_KEY:-}" ]]; then
  err "Fill at least CEREBRAS, GROQ, and GEMINI keys in $ENV_FILE"; exit 1
fi
ok "Environment file ready"

# ─── APT Dependencies ──────────────────────────────────────
log "Installing system packages..."
apt-get update -qq
apt-get install -y -qq curl git python3 python3-pip fail2ban ufw postgresql postgresql-contrib > /dev/null 2>&1
ok "System packages"

# ─── Node.js ───────────────────────────────────────────────
if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 20 ]]; then
  log "Installing Node.js 22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
  apt-get install -y -qq nodejs > /dev/null 2>&1
fi
ok "Node.js $(node -v)"

# ─── SSH Hardening ─────────────────────────────────────────
log "Hardening SSH..."
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
for f in /etc/ssh/sshd_config.d/*.conf; do
  [ -f "$f" ] && sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' "$f"
  [ -f "$f" ] && sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/g' "$f"
done
systemctl reload sshd 2>/dev/null || true
ok "SSH hardened + TCP forwarding enabled"

# ─── Firewall ──────────────────────────────────────────────
log "Configuring UFW..."
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow 2222/tcp comment 'SSH' > /dev/null 2>&1
ufw --force enable > /dev/null 2>&1
ok "UFW (SSH 2222 only, LiteLLM/dashboards localhost only)"

# ─── Fail2ban ──────────────────────────────────────────────
systemctl enable fail2ban > /dev/null 2>&1
systemctl start fail2ban
ok "Fail2ban active"

# ─── PostgreSQL ────────────────────────────────────────────
log "Setting up PostgreSQL..."
systemctl enable postgresql > /dev/null 2>&1
systemctl start postgresql
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='litellm'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER litellm WITH PASSWORD 'litellm123';" > /dev/null 2>&1
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='litellm'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE litellm OWNER litellm;" > /dev/null 2>&1
ok "PostgreSQL (litellm DB)"

# ─── LiteLLM ──────────────────────────────────────────────
log "Installing LiteLLM..."
pip3 install -q litellm[proxy] prisma 2>/dev/null
mkdir -p /opt/litellm
cp "$SCRIPT_DIR/configs/litellm-config.yaml" /opt/litellm/config.yaml
cat > /usr/local/bin/litellm << 'BINEOF'
#!/usr/bin/python3
import re, sys
from litellm.proxy.proxy_cli import run_server
if __name__ == "__main__":
    sys.argv[0] = re.sub(r"(-script\.pyw|\.exe)?$", "", sys.argv[0])
    sys.exit(run_server())
BINEOF
chmod +x /usr/local/bin/litellm
cd /usr/local/lib/python3.*/dist-packages/litellm/proxy && prisma generate > /dev/null 2>&1 || true
cd "$SCRIPT_DIR"
cp "$SCRIPT_DIR/services/litellm.service" /etc/systemd/system/
systemctl daemon-reload && systemctl enable litellm && systemctl start litellm
sleep 8
ok "LiteLLM (port 4000, localhost only)"

# ─── OpenClaw ──────────────────────────────────────────────
log "Installing OpenClaw..."
npm install -g openclaw@latest > /dev/null 2>&1
openclaw onboard --non-interactive --accept-risk 2>/dev/null || true
mkdir -p /root/.openclaw/workspace/skills
source "$ENV_FILE"
cat > /etc/openclaw.env << OCEOF
OPENAI_API_KEY=$LITELLM_MASTER_KEY
OPENAI_BASE_URL=http://127.0.0.1:4000
NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
OPENCLAW_NO_RESPAWN=1
OPENCLAW_OPENAI_API=openai-chat
OCEOF
chmod 600 /etc/openclaw.env
mkdir -p /var/tmp/openclaw-compile-cache

# Patch OpenClaw for localhost SSRF bypass + openai-chat API
PROVIDER_FILE=$(find /usr/lib/node_modules/openclaw/dist -name "openai-provider-*.js" 2>/dev/null | head -1)
STREAM_FILE=$(find /usr/lib/node_modules/openclaw/dist -name "anthropic-vertex-stream-*.js" 2>/dev/null | head -1)
if [[ -n "$STREAM_FILE" ]]; then
  sed -i 's/function resolveModelRequestPolicy(model) {/function resolveModelRequestPolicy(model) { const _hasCustomBase = Boolean(model.baseUrl \&\& !model.baseUrl.includes("api.openai.com"));/' "$STREAM_FILE"
  sed -i 's/request: getModelProviderRequestTransport(model)/request: getModelProviderRequestTransport(model), allowPrivateNetwork: _hasCustomBase/' "$STREAM_FILE"
  log "Patched SSRF bypass for localhost"
fi
if [[ -n "$PROVIDER_FILE" ]]; then
  sed -i 's/api: "openai-responses"/api: "openai-chat"/g' "$PROVIDER_FILE"
  log "Patched openai-responses -> openai-chat"
fi
systemctl stop openclaw-gateway 2>/dev/null; systemctl disable openclaw-gateway 2>/dev/null || true
cp "$SCRIPT_DIR/services/openclaw.service" /etc/systemd/system/
systemctl daemon-reload && systemctl enable openclaw && systemctl start openclaw
sleep 10
ok "OpenClaw (port 18789, localhost only)"

# ─── CashClaw ─────────────────────────────────────────────
log "Installing CashClaw..."
npm install -g cashclaw@latest > /dev/null 2>&1
mkdir -p /root/.cashclaw/missions
cashclaw skills --install 2>/dev/null || true
cp "$SCRIPT_DIR/services/cashclaw.service" /etc/systemd/system/
systemctl daemon-reload && systemctl enable cashclaw && systemctl start cashclaw
sleep 5
ok "CashClaw (dashboard port 3847)"

# ─── Mission Control ──────────────────────────────────────
log "Installing Mission Control..."
cd /root/.openclaw
if [[ ! -d openclaw-mission-control ]]; then
  git clone https://github.com/robsannaa/openclaw-mission-control.git
fi
cd openclaw-mission-control
npm ci --include=optional --no-audit --no-fund > /dev/null 2>&1
npm run build > /dev/null 2>&1
cp "$SCRIPT_DIR/services/openclaw-mission-control.service" /etc/systemd/system/
systemctl daemon-reload && systemctl enable openclaw-mission-control && systemctl start openclaw-mission-control
sleep 8
cd "$SCRIPT_DIR"
ok "Mission Control (port 3333)"

# ─── Daily Briefing Cron ──────────────────────────────────
log "Setting up daily briefing..."
cat > /opt/litellm/daily-briefing.sh << 'BRIEFEOF'
#!/bin/bash
source /home/claude/.env
L=$(systemctl is-active litellm); O=$(systemctl is-active openclaw); C=$(systemctl is-active cashclaw)
MSG="Daily Briefing — $(date +%Y-%m-%d)
System: LiteLLM=$L OpenClaw=$O CashClaw=$C"
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" -d "text=${MSG}" > /dev/null 2>&1
BRIEFEOF
chmod +x /opt/litellm/daily-briefing.sh
(crontab -l 2>/dev/null | grep -v daily-briefing; echo "0 5 * * * /opt/litellm/daily-briefing.sh") | crontab -
ok "Daily briefing (07:00 CET)"

# ─── Verification ─────────────────────────────────────────
echo ""; log "Verification..."
source "$ENV_FILE"
PASS=0; FAIL=0
check() { if eval "$2" > /dev/null 2>&1; then ok "$1"; PASS=$((PASS+1)); else err "$1"; FAIL=$((FAIL+1)); fi; }
check "LiteLLM health" "curl -sf -H 'Authorization: Bearer $LITELLM_MASTER_KEY' http://127.0.0.1:4000/health"
check "OpenClaw running" "pgrep -f openclaw-gateway"
check "CashClaw dashboard" "curl -sf http://127.0.0.1:3847/api/status"
check "Mission Control" "curl -sf http://127.0.0.1:3333/"
check "Fail2ban" "systemctl is-active fail2ban"
check "UFW" "ufw status | grep -q active"
check "Cron" "crontab -l | grep -q daily-briefing"
echo ""; log "$PASS passed, $FAIL failed"
if [[ $FAIL -eq 0 ]]; then
  echo ""; ok "All systems operational."
  echo ""
  echo "Access via SSH tunnel:"
  echo "  ssh -p 2222 -L 4000:127.0.0.1:4000 -L 3333:127.0.0.1:3333 -L 3847:127.0.0.1:3847 root@YOUR_SERVER"
  echo "  LiteLLM:         http://localhost:4000/ui"
  echo "  Mission Control: http://localhost:3333"
  echo "  CashClaw:        http://localhost:3847"
fi
