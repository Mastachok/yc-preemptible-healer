#!/usr/bin/env bash
set -euo pipefail

CFG="/etc/yc-preemptible-healer/config.env"
# shellcheck disable=SC1090
source "$CFG"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "$(ts) $*" >> "$LOG_FILE"; }

start_if_needed() {
  local id="$1"
  local name="$2"
  local status="$3"

  case "$status" in
    RUNNING) return 0 ;;
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

# -------- MODE: ids --------
if [[ "${VM_SELECT_MODE:-labels}" == "ids" ]]; then
  IFS=',' read -r -a IDS <<< "${INSTANCE_IDS}"
  for id in "${IDS[@]}"; do
    [[ -z "$id" ]] && continue
    obj=$(yc --profile "$YC_PROFILE" compute instance get --id "$id" --format json 2>/dev/null || true)
    if [[ -z "$obj" ]]; then
      log "skip unknown id=$id"
      continue
    fi
    name=$(echo "$obj" | jq -r '.name')
    status=$(echo "$obj" | jq -r '.status')
    start_if_needed "$id" "$name" "$status"
  done
  exit 0
fi

# -------- MODE: names --------
if [[ "${VM_SELECT_MODE:-labels}" == "names" ]]; then
  IFS=',' read -r -a NAMES <<< "${INSTANCE_NAMES}"
  for name in "${NAMES[@]}"; do
    [[ -z "$name" ]] && continue
    obj=$(yc --profile "$YC_PROFILE" compute instance get --name "$name" --folder-id "$FOLDER_ID" --format json 2>/dev/null || true)
    if [[ -z "$obj" ]]; then
      log "skip unknown name=$name"
      continue
    fi
    id=$(echo "$obj" | jq -r '.id')
    status=$(echo "$obj" | jq -r '.status')
    start_if_needed "$id" "$name" "$status"
  done
  exit 0
fi

# -------- MODE: labels (default) --------
yc --profile "$YC_PROFILE" compute instance list --folder-id "$FOLDER_ID" --format json |
jq -r --arg k "$LABEL_KEY" --arg v "$LABEL_VALUE" '
  .[] | select(.labels[$k]==$v) | [.id,.name,.status] | @tsv
' | while IFS=$'\t' read -r id name status; do
  start_if_needed "$id" "$name" "$status"
done
