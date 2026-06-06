#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

owner="${STARROCKS_RELEASE_OWNER:-StarRocks}"
repo="${STARROCKS_RELEASE_REPO:-starrocks}"
remote_url="${STARROCKS_RELEASE_REMOTE:-https://github.com/${owner}/${repo}.git}"

latest_stable_tag() {
  git ls-remote --tags --refs "$remote_url" \
    | sed -nE 's#^[[:xdigit:]]+[[:space:]]+refs/tags/([0-9]+(\.[0-9]+)+)$#\1#p' \
    | perl -e '
      chomp(my @tags = <>);
      @tags = sort {
        my @a_parts = split /\./, $a;
        my @b_parts = split /\./, $b;
        my $last = @a_parts > @b_parts ? $#a_parts : $#b_parts;
        my $cmp = 0;
        for my $index (0 .. $last) {
          $cmp = ($a_parts[$index] // 0) <=> ($b_parts[$index] // 0);
          last if $cmp;
        }
        $cmp;
      } @tags;
      print "$tags[-1]\n" if @tags;
    '
}

resolve_tag_commit() {
  local tag="$1"
  local commit

  commit="$(
    git ls-remote "$remote_url" "refs/tags/${tag}^{}" \
      | awk 'NR == 1 { print $1 }'
  )"
  if [[ -z "$commit" ]]; then
    commit="$(
      git ls-remote "$remote_url" "refs/tags/${tag}" \
        | awk 'NR == 1 { print $1 }'
    )"
  fi

  if [[ -z "$commit" ]]; then
    echo "could not resolve StarRocks tag: $tag" >&2
    exit 1
  fi

  printf '%s\n' "$commit"
}

prefetch_source_hash() {
  local tag="$1"
  local archive_url="https://github.com/${owner}/${repo}/archive/${tag}.tar.gz"
  local prefetch_json

  prefetch_json="$(nix store prefetch-file --json --unpack "$archive_url")"
  printf '%s\n' "$prefetch_json" \
    | sed -nE 's/^.*"hash":"([^"]+)".*$/\1/p'
}

if [[ "${1:-}" == "--print-latest" ]]; then
  latest_stable_tag
  exit 0
fi

tag="${1:-${STARROCKS_RELEASE_TAG:-}}"
if [[ -z "$tag" || "$tag" == "latest" || "$tag" == "--latest" ]]; then
  tag="$(latest_stable_tag)"
fi

if [[ -z "$tag" ]]; then
  echo "could not determine the latest stable StarRocks tag" >&2
  exit 1
fi

if [[ ! "$tag" =~ ^[0-9A-Za-z._-]+$ ]]; then
  echo "unsupported StarRocks tag syntax: $tag" >&2
  exit 1
fi

commit_hash="$(resolve_tag_commit "$tag")"
source_hash="$(prefetch_source_hash "$tag")"

if [[ -z "$source_hash" ]]; then
  echo "could not prefetch source hash for StarRocks tag: $tag" >&2
  exit 1
fi

cat > nix/starrocks-release.nix <<EOF
{
  version = "$tag";
  sourceOwner = "$owner";
  sourceRepo = "$repo";
  rev = "$tag";
  commitHash = "$commit_hash";
  sourceHash = "$source_hash";
}
EOF

printf 'updated StarRocks release pin to %s (%s)\n' "$tag" "$commit_hash"
