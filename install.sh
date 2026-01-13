#!/usr/bin/env bash
set -euo pipefail

APP="yc-preemptible-healer"
APP_DIR="/opt/$APP"
CFG_DIR="/etc/$APP"
CFG="$CFG_DIR/config.env"
LOG="/var/log/$APP.log"
PROFILE="healer"

LANG_CHOICE=""
for a in "$@"; do [[ "$a" == --lang=* ]] && LANG_CHOICE="${a#*=}"; done
[[ -z "$LANG_CHOICE" ]] && [[ "${LANG:-}" == ru* ]] && LANG_CHOICE="ru" || LANG_CHOICE="en"

t() {
  case "$LANG_CHOICE:$1" in
    ru:start) echo "Установка yc-preemptible-healer" ;;
    en:start) echo "Installing yc-preemptible-healer" ;;
    ru:folder) echo "FOLDER_ID (папка YC)" ;;
    en:folder) echo "FOLDER_ID (YC folder)" ;;
    ru:interval) echo "Интервал проверки (сек)" ;;
    en:interval) echo "Check interval (sec)" ;;
    ru:mode) echo "Выбор VM:" ;;
    en:mode) echo "VM selection:" ;;
    ru:ids) echo "1) По ID" ;;
    en:ids) echo "1) By ID" ;;
    ru:names) echo "2) По имени" ;;
    en:names) echo "2) By name" ;;
    ru:done) echo "✅ Установка завершена" ;;
    en:done) echo "✅ Installation complete" ;;
    *) echo "$1" ;;
  esac
}

echo "=== $(t start) ==="

apt-get update -y
apt-get install -y curl jq ca-certificates git

if ! command -v yc >/dev/null; then
  curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash
  ln -sf /root/yandex-cloud/bin/yc /usr/local/bin/yc
fi

mkdir -p "$APP_DIR" "$CFG_DIR"
touch "$LOG"

cp heal.sh "$APP_DIR/heal.sh"
cp manage.sh "$APP_DIR/manage.sh"
chmod +x "$APP_DIR"/*.sh
ln -sf "$APP_DIR/manage.sh" /usr/local/bin/yc-healer

read -rp "$(t folder): " FOLDER_ID
read -rp "$(t interval) [60]: " INTERVAL
INTERVAL="${INTERVAL:-60}"

echo "$(t mode)"
echo "$(t ids)"
echo "$(t names)"
read -rp "> " MODE

if [[ "$MODE" == "1" ]]; then
  VM_MODE="ids"
  read -rp "INSTANCE_IDS: " IDS
  NAMES=""
else
  VM_MODE="names"
  read -rp "INSTANCE_NAMES: " NAMES
  IDS=""
fi

cat >"$CFG" <<EOF
FOLDER_ID="$FOLDER_ID"
YC_PROFILE="$PROFILE"
INTERVAL_SEC="$INTERVAL"
LOG_FILE="$LOG"
VM_SELECT_MODE="$VM_MODE"
INSTANCE_IDS="$IDS"
INSTANCE_NAMES="$NAMES"
EOF
chmod 600 "$CFG"

yc config profile create "$PROFILE" 2>/dev/null || true
yc init --profile "$PROFILE"
yc --profile "$PROFILE" config set folder-id "$FOLDER_ID"

cp systemd/*.service systemd/*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now yc-preemptible-healer.timer

echo "$(t done)"
