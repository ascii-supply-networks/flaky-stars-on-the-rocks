#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

docker_image="${STARROCKS_NIX_DOCKER_IMAGE:-nixos/nix:2.24.11}"
docker_pull_policy="${STARROCKS_NIX_DOCKER_PULL:-missing}"

platform_for_system() {
  case "$1" in
    x86_64-linux)
      echo "linux/amd64"
      ;;
    aarch64-linux)
      echo "linux/arm64"
      ;;
    *)
      echo "unsupported Linux system for Docker hash refresh: $1" >&2
      exit 1
      ;;
  esac
}

if [[ "$#" -eq 0 ]]; then
  set -- aarch64-linux x86_64-linux
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

replace_args=()
for system in "$@"; do
  platform="$(platform_for_system "$system")"
  out_file="$tmp_dir/$system.env"

  echo "Refreshing $system hashes in Docker platform $platform"

  docker run --rm \
    --platform "$platform" \
    --pull "$docker_pull_policy" \
    -e NIX_CONFIG=$'experimental-features = nix-command flakes\nfilter-syscalls = false' \
    -e TARGET_SYSTEM="$system" \
    -v "$repo_root:/repo:ro" \
    -v "$tmp_dir:/out" \
    "$docker_image" \
    bash -euo pipefail -c '
      mkdir -p /work
      cp -a /repo/. /work/
      chmod -R u+w /work
      cd /work

      git config --global --add safe.directory /work

      nix shell nixpkgs#gnused nixpkgs#perl -c bash -euo pipefail -c '"'"'
        nix/scripts/update-fixed-output-hashes.sh "$TARGET_SYSTEM"

        read_fixed_output_hash() {
          local file="$1"

          perl -0ne "
            my \$system = quotemeta(\$ENV{\"TARGET_SYSTEM\"});
            if (/hashes\\s*=\\s*\\{\\n(.*?)^\\s*\\};/ms) {
              my \$hashes = \$1;
              if (\$hashes =~ /^[[:blank:]]*\$system[[:blank:]]*=[[:blank:]]*\"([^\"]+)\"[[:blank:]]*;/m) {
                print \$1;
                exit 0;
              }
            }
            exit 1;
          " "$file"
        }

        thirdparty_sources_hash="$(
          read_fixed_output_hash nix/packages/starrocks-thirdparty-sources.nix
        )"
        maven_repository_hash="$(
          read_fixed_output_hash nix/packages/starrocks-maven-repository.nix
        )"

        if [[ -z "$thirdparty_sources_hash" || -z "$maven_repository_hash" ]]; then
          echo "failed to read refreshed hashes for $TARGET_SYSTEM" >&2
          exit 1
        fi

        {
          printf "THIRDPARTY_SOURCES_HASH=%q\n" "$thirdparty_sources_hash"
          printf "MAVEN_REPOSITORY_HASH=%q\n" "$maven_repository_hash"
        } > "/out/$TARGET_SYSTEM.env"
      '"'"'
    '

  if [[ ! -f "$out_file" ]]; then
    echo "missing Docker hash output for $system" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$out_file"

  replace_args+=("$system" "$THIRDPARTY_SOURCES_HASH" "$MAVEN_REPOSITORY_HASH")
done

nix/scripts/update-fixed-output-hashes.sh --replace-only "${replace_args[@]}"
