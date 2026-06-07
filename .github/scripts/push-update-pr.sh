#!/usr/bin/env bash
set -euo pipefail

: "${BRANCH:?BRANCH is required}"
: "${TITLE:?TITLE is required}"
: "${COMMIT_MESSAGE:?COMMIT_MESSAGE is required}"
: "${BODY:?BODY is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SERVER_URL:?GITHUB_SERVER_URL is required}"

base_branch="${BASE_BRANCH:-main}"
manual_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/pull/new/${BRANCH}"

write_summary() {
  local status="$1"
  local url="$2"

  if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
    return 0
  fi

  {
    printf '### %s\n\n' "$status"
    printf -- '- Branch: `%s`\n' "$BRANCH"
    printf -- '- Pull request: %s\n' "$url"
  } >> "$GITHUB_STEP_SUMMARY"
}

if [[ -z "$(git status --porcelain --untracked-files=normal)" ]]; then
  printf 'No update diff to commit.\n'
  write_summary "No update diff" "$manual_url"
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if git fetch --no-tags --depth=1 origin "$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null; then
  printf 'Fetched existing update branch %s.\n' "$BRANCH"
else
  printf 'No existing remote update branch %s.\n' "$BRANCH"
fi
git checkout -B "$BRANCH"
git add -A
git commit -m "$COMMIT_MESSAGE"
git push --force-with-lease origin "$BRANCH"

export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$GH_TOKEN" ]]; then
  printf 'No GitHub token is available; pushed branch only.\n' >&2
  write_summary "Update branch pushed" "$manual_url"
  exit 0
fi

if pr_url="$(gh pr view "$BRANCH" --repo "$GITHUB_REPOSITORY" --json url --jq .url 2>/dev/null)"; then
  gh pr edit "$BRANCH" --repo "$GITHUB_REPOSITORY" --title "$TITLE" --body "$BODY"
  write_summary "Pull request updated" "$pr_url"
  exit 0
fi

set +e
pr_output="$(
  gh pr create \
    --repo "$GITHUB_REPOSITORY" \
    --head "$BRANCH" \
    --base "$base_branch" \
    --title "$TITLE" \
    --body "$BODY" 2>&1
)"
pr_status=$?
set -e

if [[ "$pr_status" -eq 0 ]]; then
  printf '%s\n' "$pr_output"
  write_summary "Pull request created" "$pr_output"
  exit 0
fi

if grep -Eqi 'GitHub Actions is not permitted to create or approve pull requests|not permitted to create.*pull requests' <<< "$pr_output"; then
  printf '::warning::GitHub Actions is not permitted to create pull requests; pushed branch only.\n'
  printf '%s\n' "$pr_output" >&2
  write_summary "Update branch pushed; create the PR manually" "$manual_url"
  exit 0
fi

printf '%s\n' "$pr_output" >&2
exit "$pr_status"
