#!/usr/bin/env bash
set -euo pipefail

CFG="/etc/yc-preemptible-healer/config.env"
# shellcheck disable=SC1090
source "$CFG"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "$(ts) $*" >> "$LOG_FILE"; }

start_if_needed() {
  local id="$1" name="$2" status="$3"
  case "$status" in
    RUNNING) return 0 ;;
    STARTING) log "skip $name ($id) status=STARTING"; return 0 ;;
    STOPPED|ERROR|CRASHED)
      log "start $name ($id) status=$status"
      yc --profile "$YC_PROFILE" compute instance start --id "$id" >> "$LOG_FILE" 2>&1 || \
        log "FAILED start $name ($id)"
      ;;
    *)
      log "skip $name ($id) status=$status"
      ;;
  esac
}

if [[ "${VM_SELECT_MODE:-ids}" == "ids" ]]; then
  IFS=',' read -r -a IDS <<< "${INSTANCE_IDS:-}"
  for id in "${IDS[@]}"; do
    id="${id// /}"
    [[ -z "$id" ]] && continue
    obj=$(yc --profile "$YC_PROFILE" compute instance get --id "$id" --format json 2>/dev/null || true)
    [[ -z "$obj" ]] && { log "skip unknown id=$id"; continue; }
    name=$(echo "$obj" | jq -r '.name')
    status=$(echo "$obj" | jq -r '.status')
    start_if_needed "$id" "$name" "$status"
  done
else
  IFS=',' read -r -a NAMES <<< "${INSTANCE_NAMES:-}"
  for name in "${NAMES[@]}"; do
    name="${name// /}"
    [[ -z "$name" ]] && continue
    obj=$(yc --profile "$YC_PROFILE" compute instance get --name "$name" --folder-id "$FOLDER_ID" --format json 2>/dev/null || true)
    [[ -z "$obj" ]] && { log "skip unknown name=$name"; continue; }
    id=$(echo "$obj" | jq -r '.id')
    status=$(echo "$obj" | jq -r '.status')
    start_if_needed "$id" "$name" "$status"
  done
fi
