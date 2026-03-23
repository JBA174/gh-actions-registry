#!/usr/bin/env bash
# check-actions.sh
# Queries the latest release version of standard GitHub Actions and displays
# them in a colored, formatted table.
#
# Usage:
#   ./check-actions.sh            # query all actions/* repos (fetched dynamically)
#   ./check-actions.sh setup      # query actions/* repos whose name contains "setup"
#   ./check-actions.sh checkout   # query actions/* repos whose name contains "checkout"

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
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

COL_ACTION=42
COL_VERSION=20
COL_DATE=25

# ---------------------------------------------------------------------------
# GitHub API
# ---------------------------------------------------------------------------
github_api() {
  local url="$1"
  local auth_args=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${auth_args[@]+"${auth_args[@]}"}" \
    "$url"
}

github_api_status() {
  local url="$1"
  local auth_args=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl -o /dev/null -sSL -w '%{http_code}' \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${auth_args[@]+"${auth_args[@]}"}" \
    "$url" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Repo inspection
# ---------------------------------------------------------------------------
is_action_repo() {
  local repo="$1"
  [[ "$(github_api_status "https://api.github.com/repos/${repo}/contents/action.yml")" == "200" ]] && return 0
  [[ "$(github_api_status "https://api.github.com/repos/${repo}/contents/action.yaml")" == "200" ]] && return 0
  return 1
}

fetch_actions_repos() {
  local filter="${1:-}"
  local page=1
  local repos=()

  while true; do
    local batch
    batch=$(github_api "https://api.github.com/orgs/actions/repos?type=public&per_page=100&page=${page}" 2>/dev/null) || break
    local names
    mapfile -t names < <(printf '%s' "$batch" | jq -r '.[].full_name // empty' | tr -d '\r')
    [[ ${#names[@]} -eq 0 ]] && break

    for name in "${names[@]}"; do
      [[ -z "$filter" || "$name" == *"$filter"* ]] && repos+=("$name")
    done
    (( page++ ))
  done

  [[ ${#repos[@]} -eq 0 ]] && return 0

  local total=${#repos[@]}
  for i in "${!repos[@]}"; do
    printf "${CLEAR_LINE}  ${CYAN}Checking${RESET} (%d/%d) %s..." "$((i + 1))" "$total" "${repos[$i]}" >&2
    is_action_repo "${repos[$i]}" && printf '%s\n' "${repos[$i]}"
  done
  printf "${CLEAR_LINE}" >&2
}

get_latest_release() {
  local repo="$1"
  local response tag published

  response=$(github_api "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null) || true
  tag=$(printf '%s' "$response" | jq -r '.tag_name // empty' | tr -d '\r')
  published=$(printf '%s' "$response" | jq -r '.published_at // empty' | tr -d '\r')

  if [[ -z "$tag" ]]; then
    response=$(github_api "https://api.github.com/repos/${repo}/tags?per_page=1" 2>/dev/null) || true
    tag=$(printf '%s' "$response" | jq -r '.[0].name // empty' | tr -d '\r')
    published=""
  fi

  echo "${tag}|${published}"
}

# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------
age_color() {
  local published="$1"
  if [[ -z "$published" ]]; then
    echo -n "$WHITE"
    return
  fi

  local epoch_published epoch_now age_days
  if date --version &>/dev/null 2>&1; then
    epoch_published=$(date -d "$published" +%s 2>/dev/null) || { echo -n "$WHITE"; return; }
  else
    epoch_published=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$published" +%s 2>/dev/null) || { echo -n "$WHITE"; return; }
  fi

  epoch_now=$(date +%s)
  age_days=$(( (epoch_now - epoch_published) / 86400 ))

  if   (( age_days <= 14 )); then echo -n "$GREEN"
  elif (( age_days <= 30 )); then echo -n "$YELLOW"
  else                            echo -n "$GREY"
  fi
}

print_separator() {
  printf "${GREY}+-%-*s-+-%-*s-+-%-*s-+${RESET}\n" \
    "$COL_ACTION" "$(printf '%*s' "$COL_ACTION" '' | tr ' ' '-')" \
    "$COL_VERSION" "$(printf '%*s' "$COL_VERSION" '' | tr ' ' '-')" \
    "$COL_DATE" "$(printf '%*s' "$COL_DATE" '' | tr ' ' '-')"
}

print_header() {
  print_separator
  printf "${BG_BLUE}${BOLD}${WHITE}| %-*s | %-*s | %-*s |${RESET}\n" \
    "$COL_ACTION" "Action" "$COL_VERSION" "Latest Version" "$COL_DATE" "Published"
  print_separator
}

print_row() {
  local action="$1" tag="$2" published="$3"
  local color disp_date
  color=$(age_color "$published")
  disp_date="${published%%T*}"
  [[ -z "$disp_date" ]] && disp_date="unknown"

  printf "${GREY}|${RESET} ${WHITE}%-*s${RESET} " "$COL_ACTION" "$action"
  printf "${GREY}|${RESET} ${color}${BOLD}%-*s${RESET} " "$COL_VERSION" "$tag"
  printf "${GREY}|${RESET} ${color}%-*s${RESET} " "$COL_DATE" "$disp_date"
  printf "${GREY}|${RESET}\n"
}

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
check_deps() {
  local missing=()
  for cmd in curl jq; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}Error: missing required tools: ${missing[*]}${RESET}" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

check_deps

FILTER="${1:-}"
mapfile -t ACTIONS < <(fetch_actions_repos "$FILTER")

echo ""
echo -e "${BOLD}${CYAN}  GitHub Actions — Latest Versions${RESET}"
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo -e "  ${YELLOW}Tip: set GITHUB_TOKEN to avoid rate-limiting (60 req/h unauthenticated)${RESET}"
fi
echo ""

declare -a RESULTS=()
for i in "${!ACTIONS[@]}"; do
  printf "${CLEAR_LINE}  ${CYAN}Fetching${RESET} (%d/%d) %s..." "$((i + 1))" "${#ACTIONS[@]}" "${ACTIONS[$i]}"
  result=$(get_latest_release "${ACTIONS[$i]}")
  tag="${result%%|*}"
  published="${result##*|}"
  [[ -n "$tag" ]] && RESULTS+=("${ACTIONS[$i]}|${tag}|${published}")
done
printf "${CLEAR_LINE}"

if [[ ${#RESULTS[@]} -gt 0 ]]; then
  mapfile -t RESULTS < <(printf '%s\n' "${RESULTS[@]}" | sort)
fi

if [[ ${#RESULTS[@]} -eq 0 ]]; then
  echo -e "${RED}No actions found${FILTER:+ matching '${FILTER}'}.${RESET}"
  echo ""
  exit 0
fi

print_header
for entry in "${RESULTS[@]}"; do
  IFS='|' read -r action tag published <<< "$entry"
  print_row "$action" "$tag" "$published"
done
print_separator

echo ""
echo -e "  Legend:  ${GREEN}${BOLD}■${RESET} ≤ 14 days   ${YELLOW}${BOLD}■${RESET} ≤ 30 days   ${GREY}■${RESET} > 30 days   ${WHITE}■${RESET} date unknown"
echo ""
