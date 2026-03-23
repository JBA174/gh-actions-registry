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
# Color / formatting helpers
# ---------------------------------------------------------------------------
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

FG_GREEN='\033[32m'
FG_YELLOW='\033[33m'
FG_CYAN='\033[36m'
FG_WHITE='\033[37m'
FG_GREY='\033[90m'
FG_RED='\033[31m'
FG_BLUE='\033[34m'

BG_HEADER='\033[44m'   # blue background for header row

# ---------------------------------------------------------------------------
# Check whether a repo actually contains an action definition file
# (action.yml or action.yaml at the root).
# Returns 0 (true) if it is an action, 1 (false) otherwise.
# ---------------------------------------------------------------------------
is_action_repo() {
  local repo="$1"
  # The Contents API returns 200 for existing files, 404 otherwise.
  # We use curl without -f so we can inspect the HTTP status ourselves.
  local status
  local auth_args=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  status=$(curl -o /dev/null -sSL -w '%{http_code}' \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${auth_args[@]+"${auth_args[@]}"}"\
    "https://api.github.com/repos/${repo}/contents/action.yml" 2>/dev/null)
  [[ "$status" == "200" ]] && return 0
  status=$(curl -o /dev/null -sSL -w '%{http_code}' \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${auth_args[@]+"${auth_args[@]}"}"\
    "https://api.github.com/repos/${repo}/contents/action.yaml" 2>/dev/null)
  [[ "$status" == "200" ]] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Dynamically fetch all public repos in the "actions" GitHub org
# and keep only the ones that contain an action definition file.
# ---------------------------------------------------------------------------
fetch_actions_repos() {
  local filter="${1:-}"
  local page=1
  local repos=()
  local batch names
  # Collect all repo names first (apply name filter immediately to skip irrelevant repos)
  while :; do
    batch=$(github_api "https://api.github.com/orgs/actions/repos?type=public&per_page=100&page=${page}" 2>/dev/null) || break
    mapfile -t names < <(printf '%s' "$batch" | jq -r '.[].full_name // empty' 2>/dev/null | tr -d '\r')
    [[ ${#names[@]} -eq 0 ]] && break
    if [[ -n "$filter" ]]; then
      local name
      for name in "${names[@]}"; do
        [[ "$name" == *"$filter"* ]] && repos+=("$name")
      done
    else
      repos+=("${names[@]}")
    fi
    (( page++ ))
  done
  if [[ ${#repos[@]} -eq 0 ]]; then
    echo -e "${FG_RED}Error: failed to fetch repos from github.com/orgs/actions — check your network or GITHUB_TOKEN${RESET}" >&2
    exit 1
  fi
  # Filter to repos that actually have action.yml / action.yaml
  local repo
  local total=${#repos[@]}
  local idx=0
  for repo in "${repos[@]}"; do
    (( idx++ )) || true
    printf '\033[2K\r  %b Checking%b (%d/%d) %s...' \
      "${FG_CYAN}" "${RESET}" "$idx" "$total" "$repo" >&2
    if is_action_repo "$repo"; then
      printf '%s\n' "$repo"
    fi
  done
  printf '\033[2K\r' >&2   # clear the progress line
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
    echo -e "${FG_RED}Error: missing required tools: ${missing[*]}${RESET}" >&2
    echo "Install them and retry." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# GitHub API helpers
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

get_latest_release() {
  local repo="$1"
  # Try /releases/latest first; fall back to /tags for repos that use tags only
  local response
  response=$(github_api "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null) || true

  local tag published
tag=$(echo "$response" | jq -r '.tag_name // empty' 2>/dev/null | tr -d '\r')
  published=$(echo "$response" | jq -r '.published_at // empty' 2>/dev/null | tr -d '\r')

  if [[ -z "$tag" ]]; then
    # Fall back to latest tag
    response=$(github_api "https://api.github.com/repos/${repo}/tags?per_page=1" 2>/dev/null) || true
    tag=$(echo "$response" | jq -r '.[0].name // empty' 2>/dev/null | tr -d '\r')
    published=""   # tags don't carry a date via this endpoint
  fi

  echo "${tag}|${published}"
}

# ---------------------------------------------------------------------------
# Age coloring
# ---------------------------------------------------------------------------
# Returns an ANSI color code based on how old the release date is.
# Green  = ≤ 14 days
# Yellow = ≤ 30 days
# Grey   = > 30 days
# White  = date unknown
age_color() {
  local published="$1"
  if [[ -z "$published" ]]; then
    echo -n "$FG_WHITE"
    return
  fi

  # Convert ISO 8601 date to epoch seconds (works on GNU date and macOS date)
  local epoch_published epoch_now age_days
  if date --version &>/dev/null 2>&1; then
    # GNU date
    epoch_published=$(date -d "$published" +%s 2>/dev/null) || { echo -n "$FG_WHITE"; return; }
  else
    # BSD/macOS date
    epoch_published=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$published" +%s 2>/dev/null) || { echo -n "$FG_WHITE"; return; }
  fi

  epoch_now=$(date +%s)
  age_days=$(( (epoch_now - epoch_published) / 86400 ))

  if   (( age_days <= 14 )); then echo -n "$FG_GREEN"
  elif (( age_days <= 30 )); then echo -n "$FG_YELLOW"
  else                            echo -n "$FG_GREY"
  fi
}

# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------
# Pad / truncate a string to exactly N chars
pad() {
  local str="$1"
  local width="$2"
  local side="${3:-left}"   # left = right-pad (default), right = left-pad
  local len=${#str}
  if (( len >= width )); then
    echo -n "${str:0:$width}"
  elif [[ "$side" == "right" ]]; then
    printf "%*s" "$width" "$str"
  else
    printf "%-*s" "$width" "$str"
  fi
}

print_separator() {
  local col1="$1" col2="$2" col3="$3"
  echo -e "${FG_GREY}+-$(printf '%0.s-' $(seq 1 $col1))-+-$(printf '%0.s-' $(seq 1 $col2))-+-$(printf '%0.s-' $(seq 1 $col3))-+${RESET}"
}

print_header() {
  local col1="$1" col2="$2" col3="$3"
  print_separator "$col1" "$col2" "$col3"
  printf "${BG_HEADER}${BOLD}${FG_WHITE}"
  printf "| %-*s | %-*s | %-*s |" "$col1" "Action" "$col2" "Latest Version" "$col3" "Published"
  printf "${RESET}\n"
  print_separator "$col1" "$col2" "$col3"
}

# ---------------------------------------------------------------------------
# Main logic  (only runs when the script is executed directly, not sourced)
# ---------------------------------------------------------------------------
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

check_deps

# Determine which actions to query.
# The optional argument is treated as a substring filter against the
# dynamically fetched list of actions/* repos (e.g. "setup" matches
# actions/setup-node, actions/setup-python, …).
FILTER="${1:-}"

mapfile -t ACTIONS < <(fetch_actions_repos "$FILTER")

if [[ ${#ACTIONS[@]} -eq 0 ]]; then
  echo -e "${FG_RED}No actions/ repos match filter: ${FILTER}${RESET}" >&2
  exit 1
fi

# Column widths
COL_ACTION=42
COL_VERSION=20
COL_DATE=25

# Header banner
echo ""
echo -e "${BOLD}${FG_CYAN}  GitHub Actions — Latest Versions${RESET}"
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo -e "  ${FG_YELLOW}Tip: set GITHUB_TOKEN to avoid rate-limiting (60 req/h unauthenticated)${RESET}"
fi
echo ""

# Collect results (action, tag, published) into an array for display
declare -a RESULTS=()

local_total=${#ACTIONS[@]}
local_idx=0
for action in "${ACTIONS[@]}"; do
  (( local_idx++ )) || true
  printf '\033[2K\r  %b Fetching%b (%d/%d) %s...' \
    "${FG_CYAN}" "${RESET}" "$local_idx" "$local_total" "$action"
  result=$(get_latest_release "$action")
  tag="${result%%|*}"
  published="${result##*|}"
  RESULTS+=("${action}|${tag:-N/A}|${published}")
done

printf '\033[2K\r'   # clear the progress line

# Sort results alphabetically by action name
mapfile -t RESULTS < <(printf '%s\n' "${RESULTS[@]}" | sort)

# Print table
if [[ ${#ACTIONS[@]} -gt 1 ]]; then
  # Multi-action table with colored version dates
  print_header "$COL_ACTION" "$COL_VERSION" "$COL_DATE"

  for entry in "${RESULTS[@]}"; do
    IFS='|' read -r action tag published <<< "$entry"
    color=$(age_color "$published")

    # Format published date for display (trim time part if present)
    disp_date="${published%%T*}"
    [[ -z "$disp_date" ]] && disp_date="unknown"

    printf "${FG_GREY}| ${RESET}"
    printf "${FG_WHITE}%-*s${RESET}" "$COL_ACTION" "$(pad "$action" "$COL_ACTION")"
    printf " ${FG_GREY}|${RESET} "
    printf "${color}${BOLD}%-*s${RESET}" "$COL_VERSION" "$(pad "$tag" "$COL_VERSION")"
    printf " ${FG_GREY}|${RESET} "
    printf "${color}%-*s${RESET}" "$COL_DATE" "$(pad "$disp_date" "$COL_DATE")"
    printf " ${FG_GREY}|${RESET}\n"
  done

  print_separator "$COL_ACTION" "$COL_VERSION" "$COL_DATE"

  # Legend
  echo ""
  echo -e "  Legend:  ${FG_GREEN}${BOLD}■${RESET} ≤ 14 days   ${FG_YELLOW}${BOLD}■${RESET} ≤ 30 days   ${FG_GREY}■${RESET} > 30 days   ${FG_WHITE}■${RESET} date unknown"
  echo ""

else
  # Single-action: show a compact detail view
  entry="${RESULTS[0]:-}"
  IFS='|' read -r action tag published <<< "$entry"
  color=$(age_color "$published")
  disp_date="${published%%T*}"
  [[ -z "$disp_date" ]] && disp_date="unknown"

  echo -e "  ${BOLD}Action   :${RESET}  ${FG_CYAN}${action}${RESET}"
  echo -e "  ${BOLD}Version  :${RESET}  ${color}${BOLD}${tag}${RESET}"
  echo -e "  ${BOLD}Published:${RESET}  ${color}${disp_date}${RESET}"
  echo ""
fi
