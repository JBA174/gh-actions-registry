#!/usr/bin/env bash
# lib/api.sh — GitHub API helpers and repo inspection

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

is_action_repo() {
  local repo="$1"
  [[ "$(github_api_status "https://api.github.com/repos/${repo}/contents/action.yml")" == "200" ]] && return 0
  [[ "$(github_api_status "https://api.github.com/repos/${repo}/contents/action.yaml")" == "200" ]] && return 0
  return 1
}

fetch_actions_repos() {
  local page=1
  local repos=()

  while true; do
    local batch
    batch=$(github_api "https://api.github.com/orgs/actions/repos?type=public&per_page=100&page=${page}" 2>/dev/null) || break
    local names
    mapfile -t names < <(printf '%s' "$batch" | jq -r '.[].full_name // empty' | tr -d '\r')
    [[ ${#names[@]} -eq 0 ]] && break

    repos+=("${names[@]}")
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
