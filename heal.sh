#!/usr/bin/env bash
set -euo pipefail

source /etc/yc-preemptible-healer/config.env

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "$(ts) $*" >> "$LOG_FILE"; }

log "start scan"

yc --profile "$YC_PROFILE" compute instance list \
  --folder-id "$FOLDER_ID" --format json | jq -r '
  .[] | [.id,.name,.status,.labels.heal] | @tsv
' | while read -r id name status heal; do
  if [[ "$heal" == "true" && "$status" != "RUNNING" ]]; then
    log "restart $name ($status)"
    yc --profile "$YC_PROFILE" compute instance start --id "$id" >> "$LOG_FILE" 2>&1 || true
  fi
done

log "scan done"
