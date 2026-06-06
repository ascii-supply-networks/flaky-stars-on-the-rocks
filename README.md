# Flaky Stars on the Rocks

Native Nix packaging for StarRocks.

This is a build and cache layer, not a replacement for StarRocks' canonical
Docker development environment. It builds the pinned StarRocks source for Linux,
provides a NixOS module, and publishes reusable binary cache closures to Cachix.

## Outputs

- `packages.<linux>.starrocks`: FE and BE server package.
- `packages.<linux>.starrocks-thirdparty`: StarRocks native third-party tree.
- `packages.<linux>.starrocks-thirdparty-sources`: vendored source archives.
- `packages.<linux>.starrocks-maven-repository`: vendored Maven repository.
- `nixosModules.starrocks`: FE/BE service module.
- `checks.<linux>.starrocks-single-node`: one FE and one BE.
- `checks.<linux>.starrocks-multinode`: one FE and two BEs.
- `devShells.<system>.default`: Linux and macOS development shell.

Package systems are `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`. The
NixOS VM outputs are Linux-only.

## Approach

The package is source-first:

1. Fetch the pinned StarRocks Git revision from `nix/starrocks-release.nix`.
2. Vendor upstream third-party source archives in a fixed-output derivation.
3. Vendor Maven dependencies in a fixed-output derivation.
4. Build StarRocks' native third-party tree.
5. Build the FE and BE server package.
6. Push the build closures to Cachix from CI.

This is not fully hermetic. StarRocks' upstream build still drives a large
third-party build and Maven dependency resolution. Nix pins the source tree,
captures the downloaded third-party and Maven inputs with fixed-output hashes,
and then builds from those pinned inputs. Updating the StarRocks revision can
therefore require refreshing hashes and adjusting compatibility patches.

The package does not use StarRocks release tarballs or prebuilt StarRocks
artifacts.

## Build

Use the Cachix cache first:

```sh
cachix use starrocks
```

Or pass it for one command:

```sh
nix build .#starrocks -L \
  --extra-substituters https://starrocks.cachix.org \
  --extra-trusted-public-keys starrocks.cachix.org-1:78NUWchpR2PhVdikbBgZyo/sh07cZCU7eOgQMzdKgNQ=
```

Then build or enter the shell:

```sh
nix develop
nix build .#starrocks -L
```

On macOS arm64, publish the server package and development closures with:

```sh
STARROCKS_CACHIX_TOKEN=... just publish-darwin-aarch
```

On macOS with Docker, refresh the Linux fixed-output hashes in Linux
containers:

```sh
just refresh-linux-hashes-docker
```

Run the single-node VM on Linux:

```sh
nix run .#starrocks-single-node-vm
```

Run smoke checks on Linux:

The `checks.<linux>.*` outputs are NixOS VM tests. They cannot run directly on
Darwin. From macOS, configure a remote Linux builder or run the checks on a
Linux machine:

```sh
nix build .#checks.x86_64-linux.starrocks-single-node -L
nix build .#checks.x86_64-linux.starrocks-multinode -L
nix build .#checks.aarch64-linux.starrocks-single-node -L
nix build .#checks.aarch64-linux.starrocks-multinode -L
```

## NixOS Module

Single node:

```nix
{
  imports = [ inputs.flaky-stars-on-the-rocks.nixosModules.starrocks ];

  services.starrocks = {
    enable = true;
    openFirewall = true;
  };
}
```

For one-BE tables, set `replication_num = "1"`.

## Updating StarRocks

The `Update StarRocks release` workflow runs on a schedule and can also be
started manually with a specific tag. It detects the latest stable upstream
StarRocks tag, updates `nix/starrocks-release.nix`, refreshes the Linux
fixed-output hashes, and opens a pull request.

Manual fallback:

1. Run `nix/scripts/update-starrocks-release.sh <tag>`.
2. Run the `Refresh fixed-output hashes` workflow.
3. Merge the generated PR.
4. Run `Build and Publish Cache`.
5. Fix package patches if the vendored third-party layout changed.

The main version knobs are already centralized in `nix/starrocks-release.nix`.
The remaining hashes are derivation-specific because they differ by system and
by vendoring step.

## CI and Cache

`CI` checks formatting, evaluates all flake outputs, and dry-runs the Linux
package plans.

`Build and Publish Cache` builds `x86_64-linux` and `aarch64-linux` on
organization GitHub-hosted runners. It publishes only through the explicit
post-build `cachix push`; automatic Cachix push is disabled.

Required GitHub Environment: `publish-nix`

- Variable: `CACHIX_CACHE_NAME`
- Secret: `CACHIX_AUTH_TOKEN`

Runner labels:

- `x86-xlarge` in group `ascii-rs`
- `aarch-xlarge` in group `ascii-rs`

The workflow uses `--cores 16 --max-jobs 1`. StarRocks fans out internally, so
running multiple Nix builds in parallel is usually worse for memory pressure.
