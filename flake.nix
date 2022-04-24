rec {
  description = "memflow physical memory introspection framework";

  inputs = {
    nixpkgs.url = github:NixOS/Nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;
    rust-overlay.url = github:oxalica/rust-overlay;

    memflow = {
      url = github:memflow/memflow;
      flake = false;
    };

    # Connector plugins

    memflow-win32 = {
      url = github:memflow/memflow-win32;
      flake = false;
    };
    memflow-kvm = {
      url = https://github.com/memflow/memflow-kvm.git;
      type = "git";
      ref = "main";
      submodules = true;
      flake = false;
    };
    memflow-qemu = {
      url = github:memflow/memflow-qemu;
      flake = false;
    };
    memflow-coredump = {
      url = github:memflow/memflow-coredump;
      flake = false;
    };
    memflow-native = {
      url = github:memflow/memflow-native;
      flake = false;
    };
    memflow-kcore = {
      url = github:memflow/memflow-kcore;
      flake = false;
    };
    memflow-microvmi = {
      url = github:memflow/memflow-microvmi;
      flake = false;
    };
    memflow-pcileech = {
      url = https://github.com/memflow/memflow-pcileech.git;
      type = "git";
      ref = "main";
      submodules = true;
      flake = false;
    };

    # Applications

    cglue-bindgen = {
      url = github:h33p/cglue;
      flake = false;
    };
    cloudflow = {
      url = github:memflow/cloudflow;
      flake = false;
    };
    scanflow = {
      url = github:memflow/scanflow;
      flake = false;
    };
    reflow = {
      url = github:memflow/reflow;
      flake = false;
    };
  };

  nixConfig = {
    extra-substituters = [ https://memflow.cachix.org ];
    extra-trusted-public-keys = [ memflow.cachix.org-1:t4ufU/+o8xtYpZQc9/AyzII/sohwMKGYNIMgT56CgXA= ];
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, ... } @ inputs:
    let
      # Function that creates the package derivation version string from the Cargo TOML version & git rev hash.
      # I'm including both the Cargo TOML version number and short VCS hash for disambiguation.
      projectVersion = cargoTOML: src: "${cargoTOML.package.version}+${builtins.substring 0 7 src.rev}";
      pkgsForSystem = system: import nixpkgs {
        inherit system;
        overlays = [
          (import rust-overlay)
          # Pin default pkgs.rustPlatform to latest stable rust toolchain version
          (self: super: {
            rustPlatform = self.makeRustPlatform (
              let
                rustToolchain = self.rust-bin.stable.latest.default;
              in
              {
                cargo = rustToolchain;
                rustc = rustToolchain;
              }
            );
          })
        ];
      };
      inherit (nixpkgs) lib;
      # List of Linux systems supported by memflow/Nix
      linuxSystems = builtins.filter # Filter out broken Linux systems that can't build all package derivations
        (platform: !(builtins.elem platform [
          "armv5tel-linux" # "error: missing bootstrap url for platform armv5te-unknown-linux-gnueabi"
          "mipsel-linux" # "error: attribute 'busybox' missing"
          "mips64el-linux" # Ditto
          "powerpc64-linux" # "error: evaluation aborted with the following error message: 'unsupported platform for the pure Linux stdenv'"
          "powerpc64le-linux" # Ditto
          "riscv32-linux" # "error: cannot coerce null to a string"
          "m68k-linux" # "error: cannot coerce null to a string"
          "s390x-linux" # Ditto
          "s390-linux" # Ditto
        ]))
        lib.platforms.linux;

      commonPkgInputs = { inherit inputs projectVersion; };
    in
    (lib.recursiveUpdate
      # Package outputs specific to Linux (KVM connector & kernel module)
      (flake-utils.lib.eachSystem linuxSystems (system:
        let
          pkgs = pkgsForSystem system;
          lib = pkgs.lib;
        in
        {
          packages = {
            memflow-kvm = pkgs.callPackage ./pkgs/connectors/kvm commonPkgInputs;
          };

          memflow-kmod = with pkgs;
            let
              memflow-kvm = self.packages.${system}.memflow-kvm;
            in
            kernel: stdenv.mkDerivation {
              name = "memflow-kmod-${memflow-kvm.version}-${kernel.version}";
              inherit (memflow-kvm) version src;

              preBuild = ''
                sed -e "s@/lib/modules/\$(.*)@${kernel.dev}/lib/modules/${kernel.modDirVersion}@" -i Makefile
              '';
              installPhase = ''
                install -D ./build/memflow.ko -t $out/lib/modules/${kernel.modDirVersion}/misc/
              '';

              hardeningDisable = [ "format" "pic" ];
              kernel = kernel.dev;
              nativeBuildInputs = kernel.moduleBuildDependencies;

              meta = with lib; {
                # See: https://github.com/memflow/memflow-kvm#licensing-note
                license = licenses.gpl2Only;
                platforms = platforms.linux;
              };
            };
        }
      ))
      (flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = pkgsForSystem system;
          lib = pkgs.lib;
        in
        {
          packages = {
            default = self.packages.${system}.memflow-ffi;

            # Memflow development package
            memflow = throw "'memflow' has been renamed to/replaced by 'memflow-ffi'";
            memflow-ffi = pkgs.callPackage ./pkgs/development/memflow (commonPkgInputs // { inherit self description; });

            # Connector Plugins

            memflow-win32 = pkgs.callPackage ./pkgs/connectors/win32 commonPkgInputs;
            memflow-qemu = pkgs.callPackage ./pkgs/connectors/qemu commonPkgInputs;
            memflow-coredump = pkgs.callPackage ./pkgs/connectors/coredump commonPkgInputs;
            memflow-native = pkgs.callPackage ./pkgs/connectors/native commonPkgInputs;
            memflow-kcore = pkgs.callPackage ./pkgs/connectors/kcore commonPkgInputs;
            # memflow-pcileech = pkgs.callPackage ./pkgs/connectors/pcileech commonPkgInputs;

            # Application Packages

            cglue-bindgen = pkgs.callPackage ./pkgs/applications/cglue-bindgen commonPkgInputs;
            cloudflow = pkgs.callPackage ./pkgs/applications/cloudflow (commonPkgInputs // {
              inherit description linuxSystems;
            });
            scanflow = pkgs.callPackage ./pkgs/applications/scanflow commonPkgInputs;
            reflow = pkgs.callPackage ./pkgs/applications/reflow (commonPkgInputs // {
              inherit description;
            });
          };
        }
      ))) // {
      nixosModule = self.nixosModules.default;
      nixosModules = {
        default = self.nixosModules.memflow;
        memflow = { config, pkgs, lib, ... }:
          let
            cfg = config.memflow;
          in
          {
            options.memflow = with lib; {
              kvm = {
                enable = mkEnableOption ''
                  Whether to enable memflow memory introspection framework for KVM. Users in the "memflow" group can
                  interact with the <command>/dev/memflow</command> device.
                '';

                loadModule = mkOption {
                  default = true;
                  type = types.bool;
                  description = "Automatically load the memflow KVM kernel module on boot";
                };

                kernelPatch = mkOption {
                  default = true;
                  type = types.bool;
                  description = "Kernel configuration that enables KALLSYMS_ALL";
                };
              };

              cloudflow = {
                enable = mkEnableOption ''
                  Whether to enable cloudflow service and FUSE file system mounting
                '';
              };
            };

            config = with lib; mkIf cfg.kvm.enable {
              boot = {
                kernelPatches = mkIf cfg.kvm.kernelPatch [
                  {
                    name = "memflow-enable-kallsyms-all";
                    patch = null;
                    extraConfig = ''
                      KALLSYMS_ALL y
                    '';
                  }
                ];
                kernelModules = mkIf cfg.kvm.loadModule [ "memflow" ];
                extraModulePackages = [
                  (self.memflow-kmod.${pkgs.system} config.boot.kernelPackages.kernel)
                ];
              };

              system.requiredKernelConfig = with config.lib.kernelConfig; [
                (isYes "KALLSYMS_ALL")
              ];

              users.groups.memflow = { };
              services.udev.extraRules = ''
                KERNEL=="memflow" SUBSYSTEM=="misc" GROUP="memflow" MODE="0660"
              '';
            };
          };
      };
    };
}
