{
  description = "Native Nix flake for StarRocks development and CI clusters";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      packageSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      devSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forSystems =
        systems: f:
        lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              overlays = [ self.overlays.default ];
            }
          )
        );

      mkApp = program: description: {
        type = "app";
        inherit program;
        meta.description = description;
      };

      singleNodeSystems = {
        starrocks-single-node = "x86_64-linux";
        starrocks-single-node-aarch64 = "aarch64-linux";
      };
      vmSystems = lib.attrValues singleNodeSystems;
      darwinCheckSystems = [ "aarch64-darwin" ];

      singleNodeConfigNames = {
        x86_64-linux = "starrocks-single-node";
        aarch64-linux = "starrocks-single-node-aarch64";
      };

      mkSingleNodeConfig =
        system:
        lib.nixosSystem {
          inherit system;
          modules = [
            { nixpkgs.overlays = [ self.overlays.default ]; }
            self.nixosModules.starrocks
            (
              { pkgs, ... }:
              {
                services.starrocks = {
                  enable = true;
                  package = pkgs.starrocks;
                  openFirewall = true;
                };

                environment.systemPackages = [ pkgs.mariadb.client ];

                boot.loader.grub.devices = [ "nodev" ];
                fileSystems."/" = {
                  device = "none";
                  fsType = "tmpfs";
                };
                system.stateVersion = "26.05";

                virtualisation.vmVariant.virtualisation = {
                  diskSize = 16384;
                  memorySize = 4096;
                };
              }
            )
          ];
        };
    in
    {
      overlays.default = final: _prev: {
        starrocks-thrift = final.callPackage ./nix/packages/starrocks-thrift.nix { };
        starrocks-maven-repository = final.callPackage ./nix/packages/starrocks-maven-repository.nix {
          thrift = final.starrocks-thrift;
        };
        starrocks-thirdparty-sources =
          final.callPackage ./nix/packages/starrocks-thirdparty-sources.nix
            { };
        starrocks-thirdparty = final.callPackage ./nix/packages/starrocks-thirdparty.nix { };
        starrocks = final.callPackage ./nix/packages/starrocks.nix { thrift = final.starrocks-thrift; };
      };

      packages = forSystems packageSystems (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
          configName = singleNodeConfigNames.${system} or null;
        in
        {
          default = pkgs.starrocks;
          starrocks = pkgs.starrocks;
          starrocks-maven-repository = pkgs.starrocks-maven-repository;
          starrocks-thirdparty = pkgs.starrocks-thirdparty;
          starrocks-thirdparty-sources = pkgs.starrocks-thirdparty-sources;
        }
        // lib.optionalAttrs (configName != null) {
          starrocks-single-node-vm = self.nixosConfigurations.${configName}.config.system.build.vm;
        }
      );

      apps = forSystems vmSystems (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
          app = mkApp "${self.packages.${system}.starrocks-single-node-vm}/bin/run-starrocks-single-node-vm" "Run a single-node StarRocks NixOS VM";
        in
        {
          default = app;
          starrocks-single-node-vm = app;
        }
      );

      devShells = forSystems devSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            curl
            jq
            mariadb.client
            maven
            openjdk21
            nixfmt
            cmake
            ninja
            gnumake
            byacc
            flex
            automake
            autoconf
            libtool
            bison
            protobuf
            python3
            starrocks-thrift
          ];
        };
      });

      formatter = forSystems devSystems (pkgs: pkgs.nixfmt-tree);

      nixosModules.default = self.nixosModules.starrocks;
      nixosModules.starrocks = import ./nix/modules/starrocks.nix;

      nixosConfigurations = lib.mapAttrs (_name: system: mkSingleNodeConfig system) singleNodeSystems;

      checks =
        (forSystems vmSystems (pkgs: {
          starrocks-single-node = import ./nix/tests/starrocks-single-node.nix {
            inherit pkgs;
            starrocksModule = self.nixosModules.starrocks;
            starrocksPackage = pkgs.starrocks;
          };

          starrocks-multinode = import ./nix/tests/starrocks-multinode.nix {
            inherit pkgs;
            starrocksModule = self.nixosModules.starrocks;
            starrocksPackage = pkgs.starrocks;
          };
        }))
        // (forSystems darwinCheckSystems (pkgs: {
          starrocks-single-node = import ./nix/tests/starrocks-darwin-single-node.nix {
            inherit pkgs;
            starrocksPackage = pkgs.starrocks;
          };
        }));
    };
}
