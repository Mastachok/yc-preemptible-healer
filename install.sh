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
    echo "Запусти от root: bash install.sh"
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
    ln -sf /root/yandex-cloud/bin/yc /usr/local/bin/yc || true
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
  cp -f ./heal.sh "$APP_DIR/heal.sh"
  chmod +x "$APP_DIR/heal.sh"

  cp -f ./systemd/yc-preemptible-healer.service /etc/systemd/system/
  cp -f ./systemd/yc-preemptible-healer.timer /etc/systemd/system/
}

configure_interactive() {
  echo "[5/7] Настройка"

  FOLDER_ID="$(ask "FOLDER_ID (папка Yandex Cloud)" "")"
  INTERVAL_SEC="$(ask "Интервал проверки (сек)" "60")"

  echo "Как выбирать VM для автоподъёма?"
  echo "  1) По метке (labels) — рекомендуемый способ"
  echo "  2) По ID (ids) — строго заданные VM"
  echo "  3) По именам (names) — строго заданные VM"
  MODE_CHOICE="$(ask "Выбери 1/2/3" "1")"

  VM_SELECT_MODE="labels"
  LABEL_KEY="heal"
  LABEL_VALUE="true"
  INSTANCE_IDS=""
  INSTANCE_NAMES=""

  case "$MODE_CHOICE" in
    1)
      VM_SELECT_MODE="labels"
      LABEL_KEY="$(ask "LABEL_KEY" "heal")"
      LABEL_VALUE="$(ask "LABEL_VALUE" "true")"
      ;;
    2)
      VM_SELECT_MODE="ids"
      INSTANCE_IDS="$(ask "INSTANCE_IDS (через запятую, без пробелов)" "")"
      if [[ -z "$INSTANCE_IDS" ]]; then
        echo "INSTANCE_IDS не может быть пустым в режиме ids"
        exit 1
      fi
      ;;
    3)
      VM_SELECT_MODE="names"
      INSTANCE_NAMES="$(ask "INSTANCE_NAMES (через запятую, без пробелов)" "")"
      if [[ -z "$INSTANCE_NAMES" ]]; then
        echo "INSTANCE_NAMES не может быть пустым в режиме names"
        exit 1
      fi
      ;;
    *)
      echo "Неверный выбор"
      exit 1
      ;;
  esac

  if [[ -z "$FOLDER_ID" ]]; then
    echo "FOLDER_ID не может быть пустым."
    exit 1
  fi

  cat > "$CFG_FILE" <<EOF
FOLDER_ID="$FOLDER_ID"
YC_PROFILE="$YC_PROFILE"
INTERVAL_SEC="$INTERVAL_SEC"
LOG_FILE="$LOG_FILE"

VM_SELECT_MODE="$VM_SELECT_MODE"    # labels | ids | names
LABEL_KEY="$LABEL_KEY"
LABEL_VALUE="$LABEL_VALUE"
INSTANCE_IDS="$INSTANCE_IDS"        # comma-separated
INSTANCE_NAMES="$INSTANCE_NAMES"    # comma-separated
EOF
  chmod 600 "$CFG_FILE"
}

oauth_login() {
  echo "[6/7] OAuth авторизация (по ссылке)"
  yc config profile create "$YC_PROFILE" >/dev/null 2>&1 || true

  echo "Сейчас yc покажет ссылку. Открой её в браузере, разреши доступ и вернись сюда."
  yc init --profile "$YC_PROFILE"

  # shellcheck disable=SC1090
  source "$CFG_FILE"
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
OnBootSec=30
OnUnitActiveSec=${INTERVAL_SEC}
AccuracySec=10s

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
  oauth_login
  enable_timer
}

main

