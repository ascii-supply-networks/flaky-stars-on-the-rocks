set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

cachix-cache := "starrocks"
darwin-system := "aarch64-darwin"

default:
    @just --list

publish: publish-darwin-aarch

# Refresh Linux fixed-output hashes from macOS using Linux Docker containers.
refresh-linux-hashes-docker:
    nix/scripts/update-fixed-output-hashes-docker.sh aarch64-linux x86_64-linux

# Build and publish the macOS arm64 package closures to Cachix.
publish-darwin-aarch:
    #!/usr/bin/env bash
    set -euo pipefail

    current_system="$(nix eval --raw --impure --expr builtins.currentSystem)"
    if [[ "$current_system" != "{{ darwin-system }}" ]]; then
      echo "publish-darwin-aarch must run on {{ darwin-system }}; current system is $current_system" >&2
      exit 1
    fi

    if [[ -z "${STARROCKS_CACHIX_TOKEN:-}" ]]; then
      echo "STARROCKS_CACHIX_TOKEN is required to push to Cachix" >&2
      exit 1
    fi

    export CACHIX_AUTH_TOKEN="$STARROCKS_CACHIX_TOKEN"
    darwin_build_cores="${NIX_BUILD_CORES:-$(sysctl -n hw.ncpu)}"
    if [[ "$darwin_build_cores" -gt 6 ]]; then
      darwin_build_cores=6
    fi
    export NIX_BUILD_CORES="$darwin_build_cores"
    export NIX_MAX_JOBS="${NIX_MAX_JOBS:-1}"

    nix/scripts/update-fixed-output-hashes.sh {{ darwin-system }}

    rm -f \
      result-{{ darwin-system }}-thirdparty-sources \
      result-{{ darwin-system }}-maven-repository \
      result-{{ darwin-system }}-thirdparty \
      result-{{ darwin-system }}-starrocks \
      result-{{ darwin-system }}-devshell \
      result-{{ darwin-system }}-formatter

    nix_build_flags=(
      --print-build-logs
      --cores "$NIX_BUILD_CORES"
      --max-jobs "$NIX_MAX_JOBS"
    )

    nix build .#packages.{{ darwin-system }}.starrocks-thirdparty-sources \
      "${nix_build_flags[@]}" \
      --out-link result-{{ darwin-system }}-thirdparty-sources

    nix build .#packages.{{ darwin-system }}.starrocks-maven-repository \
      "${nix_build_flags[@]}" \
      --out-link result-{{ darwin-system }}-maven-repository

    nix build .#packages.{{ darwin-system }}.starrocks-thirdparty \
      "${nix_build_flags[@]}" \
      --out-link result-{{ darwin-system }}-thirdparty

    nix build .#packages.{{ darwin-system }}.starrocks \
      "${nix_build_flags[@]}" \
      --out-link result-{{ darwin-system }}-starrocks

    nix develop .#default \
      --profile result-{{ darwin-system }}-devshell \
      -c true

    nix build .#formatter.{{ darwin-system }} \
      --out-link result-{{ darwin-system }}-formatter

    nix path-info --recursive \
      ./result-{{ darwin-system }}-thirdparty-sources \
      ./result-{{ darwin-system }}-maven-repository \
      ./result-{{ darwin-system }}-thirdparty \
      ./result-{{ darwin-system }}-starrocks \
      ./result-{{ darwin-system }}-devshell \
      ./result-{{ darwin-system }}-formatter \
      | sort -u \
      | nix run nixpkgs#cachix -- push {{ cachix-cache }}
