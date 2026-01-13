#!/usr/bin/env bash
set -euo pipefail

source /etc/yc-preemptible-healer/config.env

log() { echo "$(date -u +"%F %T") $*" >>"$LOG_FILE"; }

start_vm() {
  local id="$1" name="$2" status="$3"
  [[ "$status" == "RUNNING" ]] && return
  log "start $name ($id) status=$status"
  yc --profile "$YC_PROFILE" compute instance start --id "$id" >>"$LOG_FILE" 2>&1 || true
}

if [[ "$VM_SELECT_MODE" == "ids" ]]; then
  IFS=',' read -ra A <<<"$INSTANCE_IDS"
  for id in "${A[@]}"; do
    obj=$(yc --profile "$YC_PROFILE" compute instance get --id "$id" --format json 2>/dev/null || true)
    [[ -z "$obj" ]] && continue
    start_vm "$id" "$(jq -r .name <<<"$obj")" "$(jq -r .status <<<"$obj")"
  done
else
  IFS=',' read -ra A <<<"$INSTANCE_NAMES"
  for name in "${A[@]}"; do
    obj=$(yc --profile "$YC_PROFILE" compute instance get --name "$name" --folder-id "$FOLDER_ID" --format json 2>/dev/null || true)
    [[ -z "$obj" ]] && continue
    start_vm "$(jq -r .id <<<"$obj")" "$name" "$(jq -r .status <<<"$obj")"
  done
fi
