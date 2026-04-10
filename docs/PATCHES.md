# OpenClaw Patches for LiteLLM Localhost

OpenClaw v2026.4.x requires two patches to work with a local LiteLLM proxy.
These patches must be re-applied after every `npm update -g openclaw`.

## Patch 1: SSRF Bypass for Localhost

**File:** `anthropic-vertex-stream-*.js` in OpenClaw dist
**Problem:** OpenClaw blocks all HTTP requests to private/internal IPs (127.0.0.1, localhost) as SSRF protection.
**Fix:** When a custom `baseUrl` is set (not api.openai.com), allow private network access.
**Error without patch:** `[security] blocked URL fetch target=http://127.0.0.1:4000/responses reason=Blocked hostname or private/internal/special-use IP address`

## Patch 2: openai-responses to openai-chat

**File:** `openai-provider-*.js` in OpenClaw dist
**Problem:** OpenClaw calls `/responses` (OpenAI Responses API) which LiteLLM handles poorly for streaming.
**Fix:** Change all `api: "openai-responses"` to `api: "openai-chat"` so OpenClaw calls `/chat/completions` instead.
**Error without patch:** `MidStreamFallbackError` or `POST /responses 400 Bad Request`

## How to Apply

```bash
# Run the patch script (idempotent — safe to run multiple times)
./scripts/patch-openclaw.sh

# Or specify a custom OpenClaw path
./scripts/patch-openclaw.sh /usr/lib/node_modules/openclaw/dist
```

## How to Verify

```bash
# Check SSRF patch (should return 2)
grep -c "_hasCustomBase" /usr/lib/node_modules/openclaw/dist/anthropic-vertex-stream-*.js

# Check openai-chat patch (should return 6)
grep -c '"openai-chat"' /usr/lib/node_modules/openclaw/dist/openai-provider-*.js

# Check no openai-responses remain in model definitions (should return 0)
grep -c 'api: "openai-responses"' /usr/lib/node_modules/openclaw/dist/openai-provider-*.js
```

## When to Re-apply

- After `npm update -g openclaw`
- After `npm install -g openclaw@latest`
- After any OpenClaw version upgrade

The `install.sh` script applies these patches automatically during setup.
