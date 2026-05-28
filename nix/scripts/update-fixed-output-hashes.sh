#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

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

  SYSTEM="$system" HASH="$hash" perl -0pi -e '
    my $system = $ENV{"SYSTEM"};
    my $hash = $ENV{"HASH"};
    s/(\Q$system\E = ")[^"]+(";)/$1$hash$2/;
  ' "$file"
}

refresh_hash \
  "packages.x86_64-linux.starrocks-thirdparty-sources" \
  "nix/packages/starrocks-thirdparty-sources.nix" \
  "x86_64-linux"

refresh_hash \
  "packages.aarch64-linux.starrocks-thirdparty-sources" \
  "nix/packages/starrocks-thirdparty-sources.nix" \
  "aarch64-linux"

refresh_hash \
  "packages.x86_64-linux.starrocks-maven-repository" \
  "nix/packages/starrocks-maven-repository.nix" \
  "x86_64-linux"

refresh_hash \
  "packages.aarch64-linux.starrocks-maven-repository" \
  "nix/packages/starrocks-maven-repository.nix" \
  "aarch64-linux"

nix build \
  .#packages.x86_64-linux.starrocks-thirdparty-sources \
  .#packages.aarch64-linux.starrocks-thirdparty-sources \
  .#packages.x86_64-linux.starrocks-maven-repository \
  .#packages.aarch64-linux.starrocks-maven-repository \
  --no-link
