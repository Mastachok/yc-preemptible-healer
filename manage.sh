#!/usr/bin/env bash
CFG="/etc/yc-preemptible-healer/config.env"
[[ ! -f "$CFG" ]] && { echo "Config not found"; exit 1; }
source "$CFG"

B="\033[1m"; G="\033[32m"; R="\033[31m"; Y="\033[33m"; C="\033[36m"; N="\033[0m"

while true; do
  clear
  echo -e "${B}${C}YC Preemptible Healer${N}"
  echo "-----------------------------"
  echo "1) Статус таймера"
  echo "2) Запустить healer сейчас"
  echo "3) Показать лог"
  echo "4) Изменить VM (ids/names)"
  echo "5) Переавторизация OAuth"
  echo "0) Выход"
  read -rp "> " c

  case "$c" in
    1) systemctl status yc-preemptible-healer.timer --no-pager; read ;;
    2) /opt/yc-preemptible-healer/heal.sh; read ;;
    3) tail -n 100 "$LOG_FILE"; read ;;
    4) nano "$CFG"; systemctl restart yc-preemptible-healer.timer ;;
    5) yc init --profile "$YC_PROFILE"; yc config set folder-id "$FOLDER_ID" ;;
    0) exit 0 ;;
  esac
done
