#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

replace_hash() {
  local file="$1"
  local system="$2"
  local hash="$3"

  if [[ -z "$hash" ]]; then
    echo "missing hash for $system in $file" >&2
    exit 1
  fi

  SYSTEM="$system" HASH="$hash" perl -0pi -e '
    our $replaced;
    my $system = quotemeta($ENV{"SYSTEM"});
    my $hash = $ENV{"HASH"};
    $replaced += s/(hashes\s*=\s*\{\n(?:[^\n]*\n)*?[[:blank:]]*$system[[:blank:]]*=[[:blank:]]*)("[^"]+"|lib\.fakeHash)([[:blank:]]*;)/$1"$hash"$3/m;
    END { die "failed to replace hash for $ENV{SYSTEM} in $ARGV\n" unless $replaced }
  ' "$file"
}

read_hash() {
  local file="$1"
  local system="$2"

  SYSTEM="$system" perl -0ne '
    my $system = quotemeta($ENV{"SYSTEM"});
    if (/hashes\s*=\s*\{\n(.*?)^\s*};/ms) {
      my $hashes = $1;
      if ($hashes =~ /^[[:blank:]]*$system[[:blank:]]*=[[:blank:]]*"([^"]+)"[[:blank:]]*;/m) {
        print $1;
        exit 0;
      }
    }
    exit 1;
  ' "$file"
}

if [[ "${1:-}" == "--print-system" ]]; then
  system="${2:?usage: $0 --print-system <system>}"

  printf 'thirdparty-sources-hash=%s\n' "$(
    read_hash "nix/packages/starrocks-thirdparty-sources.nix" "$system"
  )"
  printf 'maven-repository-hash=%s\n' "$(
    read_hash "nix/packages/starrocks-maven-repository.nix" "$system"
  )"

  exit 0
fi

if [[ "${1:-}" == "--replace-only" ]]; then
  shift

  while [[ "$#" -gt 0 ]]; do
    if [[ "$#" -lt 3 ]]; then
      echo "usage: $0 --replace-only <system> <thirdparty-sources-hash> <maven-repository-hash> [...]" >&2
      exit 1
    fi

    system="$1"
    thirdparty_sources_hash="$2"
    maven_repository_hash="$3"
    shift 3

    replace_hash "nix/packages/starrocks-thirdparty-sources.nix" "$system" "$thirdparty_sources_hash"
    replace_hash "nix/packages/starrocks-maven-repository.nix" "$system" "$maven_repository_hash"
  done

  exit 0
fi

refresh_hash() {
  local attr="$1"
  local file="$2"
  local system="$3"

  echo "Refreshing $attr"

  local log_file
  log_file="$(mktemp)"

  set +e
  nix build ".#$attr" -L --no-link 2>&1 | tee "$log_file"
  local status="${PIPESTATUS[0]}"
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "$attr already builds with the pinned hash"
    rm -f "$log_file"
    return
  fi

  local hash
  hash="$(
    sed -nE 's/.*got:[[:space:]]*(sha256-[A-Za-z0-9+\/=]+).*/\1/p' "$log_file" \
      | tail -n 1
  )"
  rm -f "$log_file"

  if [[ -z "$hash" ]]; then
    echo "Could not find the actual hash in nix build output for $attr" >&2
    exit 1
  fi

  replace_hash "$file" "$system" "$hash"
}

refresh_system() {
  local system="$1"

  refresh_hash \
    "packages.${system}.starrocks-thirdparty-sources" \
    "nix/packages/starrocks-thirdparty-sources.nix" \
    "$system"

  refresh_hash \
    "packages.${system}.starrocks-maven-repository" \
    "nix/packages/starrocks-maven-repository.nix" \
    "$system"
}

nix_attrs=()
if [[ "$#" -eq 0 ]]; then
  set -- x86_64-linux aarch64-linux
fi

for system in "$@"; do
  refresh_system "$system"
  nix_attrs+=(
    ".#packages.${system}.starrocks-thirdparty-sources"
    ".#packages.${system}.starrocks-maven-repository"
  )
done

nix build "${nix_attrs[@]}" --no-link
