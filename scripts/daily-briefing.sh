#!/bin/bash
# Daily briefing — sends system status to Telegram at 07:00 CET
# Cron: 0 5 * * * /opt/litellm/daily-briefing.sh
source /home/claude/.env

STATUS=$(curl -s http://127.0.0.1:3847/api/status 2>/dev/null)
L=$(systemctl is-active litellm 2>/dev/null)
O=$(systemctl is-active openclaw 2>/dev/null)
C=$(systemctl is-active cashclaw 2>/dev/null)

if [ -n "$STATUS" ]; then
  EARNINGS=$(echo "$STATUS" | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  e=d['earnings']
  print('Total: \$%.2f | Today: \$%.2f (%d jobs)' % (e['total'], e['today'], e['today_count']))
except: print('unavailable')
" 2>/dev/null)
else
  EARNINGS="Dashboard offline"
fi

MSG="Daily Briefing — $(date +%Y-%m-%d)

Earnings: ${EARNINGS}

System:
  LiteLLM:  ${L}
  OpenClaw: ${O}
  CashClaw: ${C}"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "text=${MSG}" > /dev/null 2>&1
