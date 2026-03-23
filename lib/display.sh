#!/usr/bin/env bash
# lib/display.sh — Colors, column widths, and table rendering

RESET='\033[0m'
BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
WHITE='\033[37m'
GREY='\033[90m'
RED='\033[31m'
BG_BLUE='\033[44m'
CLEAR_LINE='\033[2K\r'

COL_ACTION_WIDTH=42
COL_VERSION_WIDTH=20
COL_DATE_WIDTH=25

age_color() {
  local published="$1"
  [[ -z "$published" ]] && { echo -n "$WHITE"; return; }

  local epoch_published
  epoch_published=$(date -d "$published" +%s 2>/dev/null) || { echo -n "$WHITE"; return; }

  local age_days=$(( ($(date +%s) - epoch_published) / 86400 ))

  if   (( age_days <= 14 )); then echo -n "$GREEN"
  elif (( age_days <= 30 )); then echo -n "$YELLOW"
  else                            echo -n "$GREY"
  fi
}

print_separator() {
  printf "${GREY}+-%-*s-+-%-*s-+-%-*s-+${RESET}\n" \
    "$COL_ACTION_WIDTH"  "$(printf '%*s' "$COL_ACTION_WIDTH"  '' | tr ' ' '-')" \
    "$COL_VERSION_WIDTH" "$(printf '%*s' "$COL_VERSION_WIDTH" '' | tr ' ' '-')" \
    "$COL_DATE_WIDTH"    "$(printf '%*s' "$COL_DATE_WIDTH"    '' | tr ' ' '-')"
}

print_header() {
  print_separator
  printf "${BG_BLUE}${BOLD}${WHITE}| %-*s | %-*s | %-*s |${RESET}\n" \
    "$COL_ACTION_WIDTH" "Action" "$COL_VERSION_WIDTH" "Latest Version" "$COL_DATE_WIDTH" "Published"
  print_separator
}

print_legend() {
  echo ""
  echo -e "  Legend:  ${GREEN}${BOLD}■${RESET} ≤ 14 days   ${YELLOW}${BOLD}■${RESET} ≤ 30 days   ${GREY}■${RESET} > 30 days   ${WHITE}■${RESET} date unknown"
  echo ""
}

print_row() {
  local action="$1" tag="$2" published="$3"
  local color disp_date
  color=$(age_color "$published")
  disp_date="${published%%T*}"
  [[ -z "$disp_date" ]] && disp_date="unknown"

  printf "${GREY}|${RESET} ${WHITE}%-*s${RESET} " "$COL_ACTION_WIDTH" "$action"
  printf "${GREY}|${RESET} ${color}${BOLD}%-*s${RESET} " "$COL_VERSION_WIDTH" "$tag"
  printf "${GREY}|${RESET} ${color}%-*s${RESET} " "$COL_DATE_WIDTH" "$disp_date"
  printf "${GREY}|${RESET}\n"
}
