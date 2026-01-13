#!/usr/bin/env bash
set -euo pipefail

APP="yc-preemptible-healer"
APP_DIR="/opt/$APP"
CFG_DIR="/etc/$APP"
CFG="$CFG_DIR/config.env"
LOG="/var/log/$APP.log"
PROFILE="healer"

# ---------------- UI (colors + box) ----------------
supports_color() {
  [[ -t 1 ]] || return 1
  [[ -n "${NO_COLOR:-}" ]] && return 1
  [[ "${TERM:-}" == "dumb" ]] && return 1
  return 0
}
if supports_color; then
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
  CYAN=$'\033[36m'
  GRAY=$'\033[90m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RED=$'\033[31m'
else
  BOLD=""; RESET=""; CYAN=""; GRAY=""; GREEN=""; YELLOW=""; RED=""
fi

TL="┌"; TR="┐"; BL="└"; BR="┘"; HL="─"; VL="│"

term_cols() { tput cols 2>/dev/null || echo 80; }

box_top() {
  local cols; cols="$(term_cols)"
  printf "%s%s" "${GRAY}${TL}${RESET}"
  printf "%*s" $((cols-2)) "" | tr ' ' "${HL}"
  printf "%s%s\n" "${GRAY}${TR}${RESET}" ""
}
box_line() {
  local text="$1"
  local cols; cols="$(term_cols)"
  local inner=$((cols-4))
  printf "%s%s%s " "${GRAY}${VL}${RESET}" "" ""
  printf "%-${inner}s" "$text" | cut -c1-"$inner"
  printf " %s%s\n" "${GRAY}${VL}${RESET}" ""
}
box_bot() {
  local cols; cols="$(term_cols)"
  printf "%s%s" "${GRAY}${BL}${RESET}"
  printf "%*s" $((cols-2)) "" | tr ' ' "${HL}"
  printf "%s%s\n" "${GRAY}${BR}${RESET}" ""
}

# ---------------- Language selection ----------------
LANG_CHOICE=""

# support CLI flags: --lang ru|en or --lang=ru|en
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang=ru|--lang=en) LANG_CHOICE="${1#*=}"; shift ;;
    --lang) LANG_CHOICE="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

detect_lang_auto() {
  local l="${LANG:-}"
  if [[ "$l" == ru* || "$l" == *RU* ]]; then
    echo "ru"
  else
    echo "en"
  fi
}

choose_lang_pretty() {
  # If --lang provided, use it
  if [[ "$LANG_CHOICE" == "ru" || "$LANG_CHOICE" == "en" ]]; then
    echo "$LANG_CHOICE"
    return
  fi

  local auto; auto="$(detect_lang_auto)"
  clear || true
  box_top
  box_line "${BOLD}${CYAN}Select language / Выберите язык${RESET}"
  box_line ""
  box_line "  ${BOLD}1${RESET}) English"
  box_line "  ${BOLD}2${RESET}) Русский"
  box_line ""
  box_line "${GRAY}Press 1 or 2 (auto in 5s: ${auto})${RESET}"
  box_bot

  # Read with timeout; if no input -> auto
  local ans=""
  if read -r -t 5 -p "> " ans; then
    case "${ans// /}" in
      1) echo "en" ;;
      2) echo "ru" ;;
      *) echo "$auto" ;;
    esac
  else
    echo "$auto"
  fi
}

L="$(choose_lang_pretty)"

t() {
  case "$L:$1" in
    ru:title) echo "Установка yc-preemptible-healer" ;;
    en:title) echo "Installing yc-preemptible-healer" ;;

    ru:need_root) echo "Запусти от root: bash install.sh" ;;
    en:need_root) echo "Run as root: bash install.sh" ;;

    ru:deps) echo "[1/6] Установка зависимостей" ;;
    en:deps) echo "[1/6] Installing dependencies" ;;

    ru:yc) echo "[2/6] Установка YC CLI" ;;
    en:yc) echo "[2/6] Installing YC CLI" ;;

    ru:copy) echo "[3/6] Копирование файлов" ;;
    en:copy) echo "[3/6] Copying files" ;;

    ru:setup) echo "[4/6] Настройка" ;;
    en:setup) echo "[4/6] Setup" ;;

    ru:folder) echo "FOLDER_ID (папка YC)" ;;
    en:folder) echo "FOLDER_ID (YC folder)" ;;

    ru:interval) echo "Интервал проверки (сек)" ;;
    en:interval) echo "Check interval (sec)" ;;

    ru:mode) echo "Как выбирать VM для автоподъёма?" ;;
    en:mode) echo "How to select VMs to auto-start?" ;;

    ru:mode1) echo "1) По ID (ids)" ;;
    en:mode1) echo "1) By ID (ids)" ;;

    ru:mode2) echo "2) По имени (names)" ;;
    en:mode2) echo "2) By name (names)" ;;

    ru:ids) echo "INSTANCE_IDS (через запятую)" ;;
    en:ids) echo "INSTANCE_IDS (comma-separated)" ;;

    ru:names) echo "INSTANCE_NAMES (через запятую)" ;;
    en:names) echo "INSTANCE_NAMES (comma-separated)" ;;

    ru:oauth) echo "[5/6] OAuth авторизация (по ссылке)" ;;
    en:oauth) echo "[5/6] OAuth login (via link)" ;;

    ru:oauth_hint) echo "yc покажет ссылку — открой в браузере, разреши доступ и вернись сюда." ;;
    en:oauth_hint) echo "yc will show a link — open it in a browser, allow access, then return here." ;;

    ru:timer) echo "[6/6] Включение systemd timer" ;;
    en:timer) echo "[6/6] Enabling systemd timer" ;;

    ru:done) echo "✅ Установка завершена. Запуск меню: yc-healer" ;;
    en:done) echo "✅ Installation completed. Run menu: yc-healer" ;;

    ru:err_folder) echo "FOLDER_ID не может быть пустым." ;;
    en:err_folder) echo "FOLDER_ID cannot be empty." ;;

    ru:err_list) echo "Список не может быть пустым." ;;
    en:err_list) echo "List cannot be empty." ;;

    *) echo "$1" ;;
  esac
}

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "${RED}✖${RESET} $(t need_root)"
    exit 1
  fi
}

ask() {
  local prompt="$1"
  local def="${2:-}"
  local val=""
  if [[ -n "$def" ]]; then
    read -r -p "${prompt} [${def}]: " val || true
    val="${val:-$def}"
  else
    read -r -p "${prompt}: " val || true
  fi
  echo "$val"
}

need_root
echo "${BOLD}${CYAN}=== $(t title) ===${RESET}"

echo "$(t deps)"
apt-get update -y
apt-get install -y curl jq ca-certificates git

echo "$(t yc)"
if ! command -v yc >/dev/null 2>&1; then
  curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash
  ln -sf /root/yandex-cloud/bin/yc /usr/local/bin/yc || true
else
  echo "yc: OK"
fi

echo "$(t copy)"
mkdir -p "$APP_DIR" "$CFG_DIR"
touch "$LOG"
chmod 640 "$LOG"

cp -f ./heal.sh "$APP_DIR/heal.sh"
cp -f ./manage.sh "$APP_DIR/manage.sh"
chmod +x "$APP_DIR/heal.sh" "$APP_DIR/manage.sh"
ln -sf "$APP_DIR/manage.sh" /usr/local/bin/yc-healer || true

echo "$(t setup)"
FOLDER_ID="$(ask "$(t folder)" "")"
[[ -z "$FOLDER_ID" ]] && { echo "${RED}✖${RESET} $(t err_folder)"; exit 1; }

INTERVAL="$(ask "$(t interval)" "60")"
INTERVAL="${INTERVAL:-60}"

echo "$(t mode)"
echo "  $(t mode1)"
echo "  $(t mode2)"
MODE="$(ask "1/2" "1")"

VM_MODE="ids"
IDS=""
NAMES=""

if [[ "$MODE" == "1" ]]; then
  VM_MODE="ids"
  IDS="$(ask "$(t ids)" "")"
  IDS="${IDS// /}"
  [[ -z "$IDS" ]] && { echo "${RED}✖${RESET} $(t err_list)"; exit 1; }
else
  VM_MODE="names"
  NAMES="$(ask "$(t names)" "")"
  NAMES="${NAMES// /}"
  [[ -z "$NAMES" ]] && { echo "${RED}✖${RESET} $(t err_list)"; exit 1; }
fi

cat >"$CFG" <<EOF
FOLDER_ID="$FOLDER_ID"
YC_PROFILE="$PROFILE"
INTERVAL_SEC="$INTERVAL"
LOG_FILE="$LOG"
VM_SELECT_MODE="$VM_MODE"
INSTANCE_IDS="$IDS"
INSTANCE_NAMES="$NAMES"
LANG_CHOICE="$L"
EOF
chmod 600 "$CFG"

echo "$(t oauth)"
echo "${YELLOW}!${RESET} $(t oauth_hint)"
yc config profile create "$PROFILE" 2>/dev/null || true
yc init --profile "$PROFILE"
yc --profile "$PROFILE" config set folder-id "$FOLDER_ID" >/dev/null || true

echo "$(t timer)"
cat > /etc/systemd/system/yc-preemptible-healer.service <<EOF
[Unit]
Description=YC Preemptible Healer

[Service]
Type=oneshot
ExecStart=${APP_DIR}/heal.sh
EOF

cat > /etc/systemd/system/yc-preemptible-healer.timer <<EOF
[Unit]
Description=YC Preemptible Healer Timer

[Timer]
OnBootSec=30
OnUnitActiveSec=${INTERVAL}
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now yc-preemptible-healer.timer

echo "${GREEN}✔${RESET} $(t done)"
