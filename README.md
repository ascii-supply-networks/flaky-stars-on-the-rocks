# Flaky Stars on the Rocks

Nix flake for building and running StarRocks 3.5.17 in development and CI.

## What This Provides

- `packages.x86_64-linux.starrocks`: StarRocks built from the `3.5.17` tag.
- `packages.aarch64-linux.starrocks`: same build, for Linux ARM.
- `nixosModules.starrocks`: NixOS module for FE and BE services.
- `apps.<linux-system>.starrocks-single-node-vm`: single-node NixOS VM.
- `checks.<linux-system>.starrocks-single-node`: one FE and one BE.
- `checks.<linux-system>.starrocks-multinode`: one FE and two BEs.
- `devShells.<system>.default`: Linux and macOS shell with JDK 21, Maven,
  Python, and the StarRocks-matching Thrift 0.20 compiler.

The StarRocks package is source-first. The flake fetches the StarRocks GitHub
tag, vendors the upstream source archives and Maven inputs, builds StarRocks'
native third-party tree, then builds FE and BE from source.

Maven inputs are just Java libraries needed during the FE build. The flake does
not use StarRocks release tarballs or release build artifacts.

The default build and runtime JDK is OpenJDK 21. StarRocks 3.5 requires JDK 17
or newer, and the NixOS module lets you override `services.starrocks.jdk`.

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
plans. A manual full-build workflow input builds the x86_64 Linux package and
runs the single-node VM check.

The fixed-output hashes for third-party source vendoring and Maven vendoring are
refreshed by the manual `Refresh fixed-output hashes` workflow.
