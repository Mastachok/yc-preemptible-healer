#!/usr/bin/env bash
set -euo pipefail

APP_NAME="yc-preemptible-healer"
APP_DIR="/opt/${APP_NAME}"
CFG_DIR="/etc/${APP_NAME}"
CFG_FILE="${CFG_DIR}/config.env"
LOG_FILE="/var/log/${APP_NAME}.log"
YC_PROFILE="healer"

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Запусти от root: sudo bash install.sh"
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

install_deps() {
  echo "[1/6] Установка зависимостей"
  apt-get update -y
  apt-get install -y curl jq ca-certificates git
}

install_yc() {
  echo "[2/6] Установка YC CLI"
  if command -v yc >/dev/null 2>&1; then
    echo "yc уже установлен"
  else
    curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash
    ln -sf /root/yandex-cloud/bin/yc /usr/local/bin/yc
  fi
}

setup_dirs() {
  echo "[3/6] Создание директорий"
  mkdir -p "$APP_DIR" "$CFG_DIR" /var/log
  touch "$LOG_FILE"
  chmod 640 "$LOG_FILE"
}

write_files() {
  echo "[4/6] Копирование файлов"
  cp ./heal.sh "$APP_DIR/heal.sh"
  chmod +x "$APP_DIR/heal.sh"

  cp ./systemd/yc-preemptible-healer.service /etc/systemd/system/
  cp ./systemd/yc-preemptible-healer.timer /etc/systemd/system/
}

configure_interactive() {
  echo "[5/6] Настройка"

  FOLDER_ID="$(ask "FOLDER_ID (папка Yandex Cloud)")"
  LABEL_KEY="$(ask "LABEL_KEY" "heal")"
  LABEL_VALUE="$(ask "LABEL_VALUE" "true")"
  KEY_PATH="$(ask "Путь к service-account key.json" "/root/sa-key.json")"
  INTERVAL="$(ask "Интервал проверки (сек)" "120")"

  cat > "$CFG_FILE" <<EOF
FOLDER_ID="$FOLDER_ID"
LABEL_KEY="$LABEL_KEY"
LABEL_VALUE="$LABEL_VALUE"
YC_PROFILE="$YC_PROFILE"
SERVICE_ACCOUNT_KEY="$KEY_PATH"
INTERVAL_SEC="$INTERVAL"
LOG_FILE="$LOG_FILE"
EOF

  chmod 600 "$CFG_FILE"
}

enable_timer() {
  systemctl daemon-reload
  systemctl enable --now yc-preemptible-healer.timer
}

main() {
  need_root
  install_deps
  install_yc
  setup_dirs
  write_files
  configure_interactive
  enable_timer
  echo "✅ Установка завершена"
}

main
