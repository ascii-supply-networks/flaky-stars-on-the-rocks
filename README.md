# Flaky Stars on the Rocks

Nix flake for building and running StarRocks in development and CI.

## What This Provides

- `packages.x86_64-linux.starrocks`: StarRocks built from the pinned source.
- `packages.aarch64-linux.starrocks`: same build, for Linux ARM.
- `nixosModules.starrocks`: NixOS module for FE and BE services.
- `apps.<linux-system>.starrocks-single-node-vm`: single-node NixOS VM.
- `checks.<linux-system>.starrocks-single-node`: one FE and one BE.
- `checks.<linux-system>.starrocks-multinode`: one FE and two BEs.
- `devShells.<system>.default`: Linux and macOS shell with JDK 21, Maven,
  Python, and the StarRocks-matching Thrift 0.20 compiler.

The StarRocks package is source-first. The flake fetches the pinned StarRocks
GitHub source, vendors the upstream source archives and Maven inputs, builds
StarRocks' native third-party tree, then builds FE and BE from source.

Maven inputs are just Java libraries needed during the FE build. The flake does
not use StarRocks release tarballs or release build artifacts.

The current source pin targets StarRocks PR
[`#74009`](https://github.com/StarRocks/starrocks/pull/74009) through the
`geoHeil/starrocks` PR branch so the full build can test that branch end to end.

The default build and runtime JDK is OpenJDK 21. StarRocks requires JDK 17 or
newer, and the NixOS module lets you override `services.starrocks.jdk`.

## Quick Start

Enter the flake dev shell:

```sh
nix develop
```

Or let direnv load it when you enter the checkout:

```sh
direnv allow
```

Build the package:

```sh
nix build .#starrocks
```

Run the single-node VM on Linux:

```sh
nix run .#starrocks-single-node-vm
```

Run the smoke checks:

```sh
nix build .#checks.x86_64-linux.starrocks-single-node -L
nix build .#checks.x86_64-linux.starrocks-multinode -L
nix build .#checks.aarch64-linux.starrocks-single-node -L
nix build .#checks.aarch64-linux.starrocks-multinode -L
```

On macOS, use the dev shell for source work. The FE Java modules build there,
but the full FE+BE server package and VM checks are Linux-only. StarRocks'
BE code still assumes Linux APIs and Linux shared-library layout.

## Single Node

Single node means one FE and one BE on the same NixOS host. This is the default
module shape.

```nix
{
  imports = [ inputs.flaky-stars-on-the-rocks.nixosModules.starrocks ];

  services.starrocks = {
    enable = true;
    openFirewall = true;
  };
}
```

For one-BE tables, use `replication_num = "1"`.

## Multinode

Multinode means one FE host and one or more separate BE hosts.

FE host:

```nix
{
  imports = [ inputs.flaky-stars-on-the-rocks.nixosModules.starrocks ];

  services.starrocks = {
    enable = true;
    openFirewall = true;
    be.enable = false;
  };
}
```

BE host:

```nix
{
  imports = [ inputs.flaky-stars-on-the-rocks.nixosModules.starrocks ];

  services.starrocks = {
    enable = true;
    openFirewall = true;
    fe.enable = false;

    be.instances."0" = {
      feHost = "starrocks-fe.internal";
      advertiseHost = "starrocks-be-1.internal";
    };
  };
}
```

Use more BE hosts by repeating the BE config with a different `advertiseHost`.
For two BE hosts, tables can use `replication_num = "2"`.

## CI

The main workflow installs Nix, enables the GitHub Actions backed Nix cache,
checks formatting, evaluates every flake output, and dry-runs both Linux package
plans.

The `Build and Publish Cache` workflow performs the native Linux package builds
on main-branch pushes and by manual dispatch. It runs on organization
GitHub-hosted larger runners and can push the build closures to Cachix.
Provision hosted runners with these names and runner groups:

- x86_64 runner: label `x86-xlarge`, group `ascii-rs`
- aarch64 runner: label `aarch-xlarge`, group `Default`

Create the GitHub Environment `publish-nix` and configure:

- Environment variable `CACHIX_CACHE_NAME`: Cachix cache name.
- Environment secret `CACHIX_AUTH_TOKEN`: Cachix auth token with push access.

The default build flags are `--cores 16 --max-jobs 1`. The StarRocks build
already fans out internally across `NIX_BUILD_CORES`; keep `NIX_MAX_JOBS=1`
unless the runner has enough spare memory to run independent Nix builds at the
same time.

Before relying on `Build and Publish Cache`, run `Refresh fixed-output hashes`
and merge the generated PR. The package build intentionally fails early while
the vendored third-party and Maven hashes are still `lib.fakeHash`.

The shared setup action installs Nix with `cachix/install-nix-action`, configures
Cachix when a cache name is provided, and then starts Magic Nix Cache with
FlakeHub disabled. Cachix is the binary cache publication path; Magic Nix Cache is
only used for GitHub Actions cache reuse.

The fixed-output hashes for third-party source vendoring and Maven vendoring are
refreshed by the manual `Refresh fixed-output hashes` workflow.
