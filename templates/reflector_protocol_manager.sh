#!/bin/bash
set -euo pipefail

SRC="/usr/src/xlxd/src"
CFG="$SRC/main.h"
SERVICE="xlxd.service"

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo/root."; exit 1; }
[ -f "$CFG" ] || { echo "XLXD source not found: $CFG"; exit 1; }

NAMES=("DExtra" "DPlus" "DCS" "XLX interlink" "DMR+" "DMR/MMDVM" "YSF" "Icom G3 Terminal" "Yaesu IMRS")
ENABLES=("ENABLE_DEXTRA" "ENABLE_DPLUS" "ENABLE_DCS" "ENABLE_XLX" "ENABLE_DMRPLUS" "ENABLE_DMRMMDVM" "ENABLE_YSF" "ENABLE_G3" "ENABLE_IMRS")
PORTS=("DEXTRA_PORT" "DPLUS_PORT" "DCS_PORT" "XLX_PORT" "DMRPLUS_PORT" "DMRMMDVM_PORT" "YSF_PORT" "G3_DV_PORT" "IMRS_PORT")
DEFAULTS=("30001" "20001" "30051" "10002" "8880" "62030" "42000" "40000" "21110")

get_define(){ awk -v k="$1" '$1=="#define" && $2==k {print $3; exit}' "$CFG"; }
set_define(){ local k="$1" v="$2"; sed -Ei "s|^(#define[[:space:]]+$k[[:space:]]+)[0-9]+|\\1$v|" "$CFG"; }
mode(){ [ "$(get_define "$1")" = "1" ] && echo "ON" || echo "OFF"; }

show_status(){
  echo; echo "NEW REFLECTOR - PROTOCOL / PORT MANAGEMENT"; echo "------------------------------------------------------------"
  printf "%-3s %-20s %-5s %-8s\n" "#" "Protocol" "Mode" "UDP Port"
  for i in "${!NAMES[@]}"; do printf "%-3s %-20s %-5s %-8s\n" "$((i+1))" "${NAMES[$i]}" "$(mode "${ENABLES[$i]}")" "$(get_define "${PORTS[$i]}")"; done
  printf "%-3s %-20s %-5s %-8s\n" "A" "AMBE controller" "--" "$(get_define TRANSCODER_PORT)"
  if systemctl is-enabled --quiet ambed.service 2>/dev/null; then echo "AMBED service: ENABLED"; elif systemctl list-unit-files ambed.service >/dev/null 2>&1; then echo "AMBED service: DISABLED"; else echo "AMBED service: NOT INSTALLED"; fi
  echo
}

edit_protocol(){
  local i="$1" ans port
  echo "${NAMES[$i]}: $(mode "${ENABLES[$i]}"), UDP $(get_define "${PORTS[$i]}")"
  read -rp "Enable protocol? [Y/N]: " ans
  case "${ans^^}" in Y) set_define "${ENABLES[$i]}" 1;; N) set_define "${ENABLES[$i]}" 0;; *) echo "No change."; return;; esac
  if [ "${ans^^}" = "Y" ]; then
    read -rp "UDP port [ENTER keeps $(get_define "${PORTS[$i]}"), standard ${DEFAULTS[$i]}]: " port
    if [ -n "$port" ]; then [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { echo "Invalid port."; return 1; }; set_define "${PORTS[$i]}" "$port"; fi
  fi
  echo "Saved. Select R to rebuild/restart XLXD."
}

edit_ambe_port(){
  local port; read -rp "AMBE controller UDP port [ENTER keeps $(get_define TRANSCODER_PORT), standard 10100]: " port; [ -z "$port" ] && return
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { echo "Invalid port."; return 1; }
  set_define TRANSCODER_PORT "$port"; echo "Saved. Select R to rebuild/restart XLXD."
}

toggle_ambed(){
  if ! systemctl list-unit-files ambed.service >/dev/null 2>&1; then echo "AMBED service is not installed. Install it first with the AMBED installer."; return; fi
  if systemctl is-enabled --quiet ambed.service 2>/dev/null; then systemctl disable --now ambed.service; echo "AMBED disabled and stopped."; else systemctl enable --now ambed.service; echo "AMBED enabled and started."; fi
}

apply_changes(){
  echo "Rebuilding XLXD..."
  cp -a "$CFG" "$CFG.bak.$(date +%Y%m%d-%H%M%S)"
  cd "$SRC"; make clean; make; make install; systemctl restart "$SERVICE"; sleep 1
  systemctl is-active --quiet "$SERVICE" && echo "XLXD rebuilt and restarted successfully." || { echo "XLXD restart failed. Check systemctl status $SERVICE"; exit 1; }
}

while true; do
  show_status
  echo "1-9) Change protocol ON/OFF or port"; echo "A) Change AMBE controller port"; echo "B) Enable/disable installed AMBED service"; echo "R) Apply: rebuild and restart XLXD"; echo "X) Exit"
  read -rp "Selection: " choice
  case "${choice^^}" in [1-9]) edit_protocol "$((choice-1))";; A) edit_ambe_port;; B) toggle_ambed;; R) apply_changes;; X) exit 0;; *) echo "Invalid selection.";; esac
done
