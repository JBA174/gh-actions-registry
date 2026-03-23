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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Libraries
# ---------------------------------------------------------------------------
# shellcheck source=lib/api.sh
source "${SCRIPT_DIR}/lib/api.sh"
# shellcheck source=lib/cache.sh
source "${SCRIPT_DIR}/lib/cache.sh"
# shellcheck source=lib/display.sh
source "${SCRIPT_DIR}/lib/display.sh"

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

echo ""
echo -e "${BOLD}${CYAN}  GitHub Actions — Latest Versions${RESET}"
[[ -z "${GITHUB_TOKEN:-}" ]] && \
  echo -e "  ${YELLOW}Tip: set GITHUB_TOKEN to avoid rate-limiting (60 req/h unauthenticated)${RESET}"
echo ""

declare -a RESULTS=()
if cache_is_valid; then
  echo -e "  ${GREY}Using cached results (< 24 h old). Delete .actions-cache to force refresh.${RESET}"
  echo ""
  cache_read "$FILTER"
else
  mapfile -t ACTIONS < <(fetch_actions_repos)

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
    cache_write
    if [[ -n "$FILTER" ]]; then
      local_filtered=()
      for entry in "${RESULTS[@]}"; do
        [[ "$entry" == *"$FILTER"* ]] && local_filtered+=("$entry")
      done
      RESULTS=("${local_filtered[@]:-}")
    fi
  fi
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
print_legend
