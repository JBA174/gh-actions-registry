#!/usr/bin/env bash
# lib/cache.sh — Single-file result cache with a 24-hour TTL

CACHE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.actions-cache"
CACHE_TTL_SECONDS=86400   # 24 hours

cache_is_valid() {
  [[ -f "$CACHE_FILE" ]] || return 1
  local modified age
  modified=$(date -r "$CACHE_FILE" +%s 2>/dev/null) || return 1
  age=$(( $(date +%s) - modified ))
  (( age < CACHE_TTL_SECONDS ))
}

# Reads all cached entries, then filters by $1 if provided.
# Populates the global RESULTS array.
cache_read() {
  local filter="$1"
  local all_results
  mapfile -t all_results < "$CACHE_FILE"
  if [[ -z "$filter" ]]; then
    RESULTS=("${all_results[@]}")
  else
    RESULTS=()
    local entry
    for entry in "${all_results[@]}"; do
      [[ "$entry" == *"$filter"* ]] && RESULTS+=("$entry")
    done
  fi
}

# Writes the global RESULTS array to the cache file.
cache_write() {
  printf '%s\n' "${RESULTS[@]}" > "$CACHE_FILE"
}
