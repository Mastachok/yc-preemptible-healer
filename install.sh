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
  echo "[1/7] Установка зависимостей"
  apt-get update -y
  apt-get install -y curl jq ca-certificates git
}

install_yc() {
  echo "[2/7] Установка YC CLI"
  if command -v yc >/dev/null 2>&1; then
    echo "yc уже установлен"
  else
    curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash
    ln -sf /root/yandex-cloud/bin/yc /usr/local/bin/yc
  fi
}

setup_dirs() {
  echo "[3/7] Создание директорий"
  mkdir -p "$APP_DIR" "$CFG_DIR" /var/log
  touch "$LOG_FILE"
  chmod 640 "$LOG_FILE"
}

write_files() {
  echo "[4/7] Копирование файлов"
  cp ./heal.sh "$APP_DIR/heal.sh"
  chmod +x "$APP_DIR/heal.sh"

  cp ./systemd/yc-preemptible-healer.service /etc/systemd/system/
  cp ./systemd/yc-preemptible-healer.timer /etc/systemd/system/
}

configure_interactive() {
  echo "[5/7] Настройка"

  echo "Выбери метод авторизации:"
  echo "  1) OAuth через ссылку (быстро, удобно)"
  echo "  2) Service Account key.json (рекомендуется для серверов)"
  AUTH_METHOD="$(ask "Введи 1 или 2" "1")"

  FOLDER_ID="$(ask "FOLDER_ID (папка Yandex Cloud)" "")"
  LABEL_KEY="$(ask "LABEL_KEY (метка для отбора VM)" "heal")"
  LABEL_VALUE="$(ask "LABEL_VALUE (значение метки)" "true")"
  INTERVAL="$(ask "Интервал проверки (сек)" "120")"

  SERVICE_ACCOUNT_KEY=""
  if [[ "$AUTH_METHOD" == "2" ]]; then
    SERVICE_ACCOUNT_KEY="$(ask "Путь к service-account key.json" "/root/sa-key.json")"
  fi

  if [[ -z "$FOLDER_ID" ]]; then
    echo "FOLDER_ID не может быть пустым."
    exit 1
  fi

  cat > "$CFG_FILE" <<EOF
AUTH_METHOD="$AUTH_METHOD"   # 1=OAuth, 2=ServiceAccount
FOLDER_ID="$FOLDER_ID"
LABEL_KEY="$LABEL_KEY"
LABEL_VALUE="$LABEL_VALUE"
YC_PROFILE="$YC_PROFILE"
SERVICE_ACCOUNT_KEY="$SERVICE_ACCOUNT_KEY"
INTERVAL_SEC="$INTERVAL"
LOG_FILE="$LOG_FILE"
EOF
  chmod 600 "$CFG_FILE"
}

setup_yc_auth() {
  echo "[6/7] Авторизация YC CLI"
  # shellcheck disable=SC1090
  source "$CFG_FILE"

  yc config profile create "$YC_PROFILE" >/dev/null 2>&1 || true

  if [[ "$AUTH_METHOD" == "1" ]]; then
    echo "OAuth авторизация: сейчас yc покажет ссылку — открой её в браузере и подтверди."
    echo "После подтверждения вернись в терминал и продолжай."
    yc init --profile "$YC_PROFILE"
  else
    if [[ -z "${SERVICE_ACCOUNT_KEY}" || ! -f "${SERVICE_ACCOUNT_KEY}" ]]; then
      echo "Не найден key.json по пути: ${SERVICE_ACCOUNT_KEY}"
      echo "Положи файл и перезапусти install.sh"
      exit 1
    fi
    yc --profile "$YC_PROFILE" config set service-account-key "$SERVICE_ACCOUNT_KEY" >/dev/null
    yc --profile "$YC_PROFILE" config set folder-id "$FOLDER_ID" >/dev/null
  fi

  # На всякий — выставим folder-id и в OAuth профиле тоже
  yc --profile "$YC_PROFILE" config set folder-id "$FOLDER_ID" >/dev/null || true
}

enable_timer() {
  echo "[7/7] Включение systemd timer"
  # shellcheck disable=SC1090
  source "$CFG_FILE"

  cat > /etc/systemd/system/yc-preemptible-healer.timer <<EOF
[Unit]
Description=YC Preemptible Healer Timer

[Timer]
OnBootSec=60
OnUnitActiveSec=${INTERVAL_SEC}
AccuracySec=15s

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now yc-preemptible-healer.timer
  echo "✅ Установка завершена"
}

main() {
  need_root
  install_deps
  install_yc
  setup_dirs
  write_files
  configure_interactive
  setup_yc_auth
  enable_timer
}

main
