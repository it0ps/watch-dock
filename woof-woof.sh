#!/usr/bin/env bash
set -euo pipefail
#envs
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
CONTAINER_NAME_REGEX="${CONTAINER_NAME_REGEX:-.*}"
STATE_FILE="${STATE_FILE:-/opt/watch-dock/state.json}"
SEND_ON_FIRST_SEEN="${SEND_ON_FIRST_SEEN:-0}"  # 1 - yes; 0 - no
HOSTNAME_SHORT="${HOSTNAME_SHORT:-$(hostname -s 2>/dev/null || uname -n 2>/dev/null || echo host)}"

#requirements
if [ -z "${TELEGRAM_BOT_TOKEN}" ] || [ -z "${TELEGRAM_CHAT_ID}" ]; then
  echo "ERROR: envs arent set TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID"
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl required"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker required"; exit 1; }

#init
mkdir -p "$(dirname "$STATE_FILE")"
if [ ! -f "$STATE_FILE" ]; then
  echo '{}' > "$STATE_FILE"
fi
STATE="$(cat "$STATE_FILE")"
UPDATED_STATE="$STATE"

# name|image|imageID|containerID
#mapfile -t LINES < <(docker ps --format '{{.Names}}|{{.Image}}|{{.ImageID}}|{{.ID}}' | grep -E "$CONTAINER_NAME_REGEX" || true)
mapfile -t LINES < <(docker ps --no-trunc --format '{{.Names}}|{{.Image}}|{{.ID}}' \
  | grep -E "$CONTAINER_NAME_REGEX" || true)

send_tg() {
  local text="$1"
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    --data-urlencode text="$text" \
    -d parse_mode="Markdown" >/dev/null
}

ts() { date -u +"%Y-%m-%d %H:%M:%SZ"; }

CHANGES=0
for line in "${LINES[@]:-}"; do
  IFS='|' read -r cname image cid <<< "$line"

  # image id (sha256:...)
  image_id="$(docker inspect -f '{{.Image}}' "$cid" 2>/dev/null || true)"
  repo_digest="$(docker inspect -f '{{join .RepoDigests ", "}}' "$image_id" 2>/dev/null || true)"

  # choosing best anchor to trigger 
  if [ -n "$repo_digest" ] && [ "$repo_digest" != "<no value>" ]; then
    curr="$repo_digest"
  elif [ -n "$image_id" ] && [ "$image_id" != "<no value>" ]; then
    curr="$image_id"
  else
    curr="$image"  # fallback: repo:tag
  fi

  prev="$(echo "$STATE" | jq -r --arg k "$cname" '.[$k].ref // empty')"

  if [ -z "$prev" ]; then
    # first seen containers
    UPDATED_STATE="$(echo "$UPDATED_STATE" | jq --arg k "$cname" --arg im "$image" --arg rf "$curr" \
      '.[$k] = {image:$im, ref:$rf, first_seen:(now|todate)}')"
    if [ "$SEND_ON_FIRST_SEEN" = "1" ]; then
      send_tg "🆕 *${cname}* on \`${HOSTNAME_SHORT}\`
*image*: \`${image}\`
*ref*: \`${curr}\`
_time: $(ts)_"
    fi
    continue
  fi

  if [ "$curr" != "$prev" ]; then
    UPDATED_STATE="$(echo "$UPDATED_STATE" | jq --arg k "$cname" --arg im "$image" --arg rf "$curr" \
      '.[$k].image=$im | .[$k].ref=$rf | .[$k].updated=(now|todate)')"

    short_prev="${prev:0:200}"
    short_curr="${curr:0:200}"
    msg="🚀 *DEPLOY DETECTED* на \`${HOSTNAME_SHORT}\`
*container*: \`${cname}\`
*image*: \`${image}\`
*was*: \`${short_prev}\`
*now*: \`${short_curr}\`
_time: $(ts)_"
    send_tg "$msg"
  fi
done

#flushing old containers state
CURRENT_NAMES_JSON="$(printf '%s\n' "${LINES[@]:-}" | awk -F'|' 'NF{print $1}' | jq -R . | jq -s .)"
UPDATED_STATE="$(jq --argjson keep "$CURRENT_NAMES_JSON" 'with_entries(select(.key as $k | $keep | index($k)))' <<< "$UPDATED_STATE")"

#save state
echo "$UPDATED_STATE" > "$STATE_FILE"
# echo "Changes: $CHANGES"
