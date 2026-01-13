#!/usr/bin/env bash
set -euo pipefail

CFG="/etc/yc-preemptible-healer/config.env"
# shellcheck disable=SC1090
source "$CFG"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "$(ts) $*" >> "$LOG_FILE"; }

log "start scan"

yc --profile "$YC_PROFILE" compute instance list \
  --folder-id "$FOLDER_ID" --format json |
jq -r --arg k "$LABEL_KEY" --arg v "$LABEL_VALUE" '
  .[] | select(.labels[$k]==$v) | [.id,.name,.status] | @tsv
' | while IFS=$'\t' read -r id name status; do
  case "$status" in
    RUNNING)
      ;;
    STOPPED|ERROR|CRASHED)
      log "start $name ($id) status=$status"
      yc --profile "$YC_PROFILE" compute instance start --id "$id" >> "$LOG_FILE" 2>&1 || \
        log "FAILED start $name ($id)"
      ;;
    *)
      log "skip $name ($id) status=$status"
      ;;
  esac
done

log "scan done"
