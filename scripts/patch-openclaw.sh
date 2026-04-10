#!/usr/bin/env bash
# patch-openclaw.sh — Apply required patches for OpenClaw + LiteLLM localhost
# Run after: npm install -g openclaw@latest
# Safe to run multiple times (idempotent)
set -euo pipefail

RED="\033[0;31m"; GREEN="\033[0;32m"; NC="\033[0m"
ok()  { printf "${GREEN}[ok]${NC} %s\n" "$*"; }
err() { printf "${RED}[!!]${NC} %s\n" "$*" >&2; }

OPENCLAW_DIR="${1:-/usr/lib/node_modules/openclaw/dist}"

if [ ! -d "$OPENCLAW_DIR" ]; then
  err "OpenClaw dist not found at $OPENCLAW_DIR"
  exit 1
fi

# ─── PATCH 1: SSRF bypass for localhost ─────────────────────
# OpenClaw blocks all private IPs (127.0.0.1) by default.
# This patch allows LLM requests to localhost when a custom baseUrl is set.
STREAM_FILE=$(find "$OPENCLAW_DIR" -name "anthropic-vertex-stream-*.js" | head -1)

if [ -z "$STREAM_FILE" ]; then
  err "Stream file not found — OpenClaw structure may have changed"
  exit 1
fi

if grep -q "_hasCustomBase" "$STREAM_FILE"; then
  ok "SSRF patch already applied"
else
  sed -i 's/function resolveModelRequestPolicy(model) {/function resolveModelRequestPolicy(model) { const _hasCustomBase = Boolean(model.baseUrl \&\& !model.baseUrl.includes("api.openai.com"));/' "$STREAM_FILE"
  sed -i 's/request: getModelProviderRequestTransport(model)/request: getModelProviderRequestTransport(model), allowPrivateNetwork: _hasCustomBase/' "$STREAM_FILE"
  if grep -q "_hasCustomBase" "$STREAM_FILE"; then
    ok "SSRF patch applied to $(basename "$STREAM_FILE")"
  else
    err "SSRF patch failed"
    exit 1
  fi
fi

# ─── PATCH 2: openai-responses → openai-chat ───────────────
# OpenClaw calls /responses (OpenAI Responses API) by default.
# LiteLLM supports /chat/completions. This patch switches the API.
PROVIDER_FILE=$(find "$OPENCLAW_DIR" -name "openai-provider-*.js" | head -1)

if [ -z "$PROVIDER_FILE" ]; then
  err "Provider file not found — OpenClaw structure may have changed"
  exit 1
fi

CHAT_COUNT=$(grep -c '"openai-chat"' "$PROVIDER_FILE" 2>/dev/null || echo 0)
RESP_COUNT=$(grep -c 'api: "openai-responses"' "$PROVIDER_FILE" 2>/dev/null || echo 0)

if [ "$RESP_COUNT" -eq 0 ] && [ "$CHAT_COUNT" -gt 0 ]; then
  ok "openai-chat patch already applied"
else
  sed -i 's/api: "openai-responses"/api: "openai-chat"/g' "$PROVIDER_FILE"
  NEW_COUNT=$(grep -c '"openai-chat"' "$PROVIDER_FILE" 2>/dev/null || echo 0)
  if [ "$NEW_COUNT" -gt 0 ]; then
    ok "openai-chat patch applied ($NEW_COUNT replacements in $(basename "$PROVIDER_FILE"))"
  else
    err "openai-chat patch failed"
    exit 1
  fi
fi

# ─── Verify ─────────────────────────────────────────────────
echo ""
echo "Verification:"
echo "  SSRF:         $(grep -c '_hasCustomBase' "$STREAM_FILE") references"
echo "  openai-chat:  $(grep -c '"openai-chat"' "$PROVIDER_FILE") references"
echo "  openai-resp:  $(grep -c 'api: "openai-responses"' "$PROVIDER_FILE") remaining (should be 0)"
echo ""
ok "All patches applied. Restart OpenClaw: systemctl restart openclaw"
