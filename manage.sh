#!/usr/bin/env bash
set -euo pipefail

APP="yc-preemptible-healer"
APP_DIR="/opt/$APP"
CFG="/etc/$APP/config.env"
LOG_DEFAULT="/var/log/$APP.log"
TIMER="yc-preemptible-healer.timer"
SERVICE="yc-preemptible-healer.service"

[[ -f "$CFG" ]] && source "$CFG" || true
LANG_CHOICE="${LANG_CHOICE:-en}"
LOG_FILE="${LOG_FILE:-$LOG_DEFAULT}"
YC_PROFILE="${YC_PROFILE:-healer}"

supports_color() {
  [[ -t 1 ]] || return 1
  [[ -n "${NO_COLOR:-}" ]] && return 1
  [[ "${TERM:-}" == "dumb" ]] && return 1
  return 0
}
if supports_color; then
  BOLD=$'\033[1m'; RESET=$'\033[0m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  CYAN=$'\033[36m'; GRAY=$'\033[90m'; MAG=$'\033[35m'
else
  BOLD=""; RESET=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; GRAY=""; MAG=""
fi

t() {
  local k="$1"
  case "$LANG_CHOICE:$k" in
    ru:title) echo "YC Preemptible Healer — меню" ;;
    en:title) echo "YC Preemptible Healer — menu" ;;
    ru:hint) echo "Выбери пункт и нажми Enter" ;;
    en:hint) echo "Choose an option and press Enter" ;;
    ru:status) echo "Статус таймера/сервиса" ;;
    en:status) echo "Timer/service status" ;;
    ru:run) echo "Запустить healer сейчас (one-shot)" ;;
    en:run) echo "Run healer now (one-shot)" ;;
    ru:log) echo "Показать лог (последние 200 строк)" ;;
    en:log) echo "Show log (last 200 lines)" ;;
    ru:logf) echo "Смотреть лог онлайн (Ctrl+C выйти)" ;;
    en:logf) echo "Follow log (Ctrl+C to exit)" ;;
    ru:edit) echo "Изменить VM (ids/names) и список" ;;
    en:edit) echo "Edit VM mode (ids/names) and list" ;;
    ru:interval) echo "Изменить интервал таймера" ;;
    en:interval) echo "Change timer interval" ;;
    ru:reauth) echo "Переавторизация OAuth (yc init)" ;;
    en:reauth) echo "Re-auth OAuth (yc init)" ;;
    ru:restart) echo "Перезапустить таймер" ;;
    en:restart) echo "Restart timer" ;;
    ru:exit) echo "Выход" ;;
    en:exit) echo "Exit" ;;
    ru:press) echo "Нажми Enter..." ;;
    en:press) echo "Press Enter..." ;;
    *) echo "$k" ;;
  esac
}

badge() {
  local unit="$1"
  local st; st="$(systemctl is-active "$unit" 2>/dev/null || true)"
  case "$st" in
    active) echo "${GREEN}● active${RESET}" ;;
    inactive) echo "${YELLOW}● inactive${RESET}" ;;
    failed) echo "${RED}● failed${RESET}" ;;
    *) echo "${GRAY}● ${st:-unknown}${RESET}" ;;
  esac
}

pause(){ read -r -p "$(t press)" _ || true; }

while true; do
  clear || true
  echo "${BOLD}${CYAN}$(t title)${RESET}"
  echo "${GRAY}Timer:${RESET} $(badge "$TIMER")   ${GRAY}Service:${RESET} $(badge "$SERVICE")"
  echo "${GRAY}Profile:${RESET} ${YC_PROFILE}   ${GRAY}Mode:${RESET} ${VM_SELECT_MODE:-ids}"
  echo
  echo "${DIM:-}${t hint}${RESET:-}" 2>/dev/null || true
  echo "1) $(t status)"
  echo "2) $(t run)"
  echo "3) $(t log)"
  echo "4) $(t logf)"
  echo "5) $(t edit)"
  echo "6) $(t interval)"
  echo "7) $(t reauth)"
  echo "8) $(t restart)"
  echo "0) $(t exit)"
  echo
  read -r -p "> " c || true

  case "$c" in
    1) systemctl status "$TIMER" --no-pager; echo; systemctl status "$SERVICE" --no-pager || true; pause ;;
    2) "$APP_DIR/heal.sh" || true; pause ;;
    3) tail -n 200 "$LOG_FILE" 2>/dev/null || true; pause ;;
    4) tail -f "$LOG_FILE" ;;
    5) nano "$CFG"; systemctl restart "$TIMER" || true; pause ;;
    6)
      source "$CFG"
      read -r -p "INTERVAL_SEC [${INTERVAL_SEC:-60}]: " ni || true
      ni="${ni:-${INTERVAL_SEC:-60}}"
      [[ "$ni" =~ ^[0-9]+$ ]] || { echo "number only"; pause; continue; }
      tmp="$(mktemp)"
      awk -v v="$ni" '
        /^INTERVAL_SEC=/ {print "INTERVAL_SEC=\""v"\""; next}
        {print}
      ' "$CFG" > "$tmp"
      mv "$tmp" "$CFG"
      chmod 600 "$CFG"
      cat > /etc/systemd/system/yc-preemptible-healer.timer <<EOF
[Unit]
Description=YC Preemptible Healer Timer
[Timer]
OnBootSec=30
OnUnitActiveSec=${ni}
AccuracySec=10s
[Install]
WantedBy=timers.target
EOF
      systemctl daemon-reload
      systemctl restart "$TIMER" || systemctl enable --now "$TIMER"
      pause
      ;;
    7) yc init --profile "$YC_PROFILE"; source "$CFG"; yc --profile "$YC_PROFILE" config set folder-id "$FOLDER_ID" >/dev/null || true; pause ;;
    8) systemctl daemon-reload; systemctl restart "$TIMER" || systemctl enable --now "$TIMER"; pause ;;
    0) exit 0 ;;
    *) pause ;;
  esac
done
