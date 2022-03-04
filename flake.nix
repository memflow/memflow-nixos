rec {
  description = "memflow physical memory introspection framework";

  inputs = {
    rust-overlay.url = github:oxalica/rust-overlay;

    cglue-bindgen = {
      url = github:h33p/cglue;
      flake = false;
    };

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

    # Applications

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

  outputs = { self, nixpkgs, flake-utils, rust-overlay, ... } @ inputs:
    let
      # Function that creates the package derivation version string from the Cargo TOML version & git rev hash.
      # I'm including both the Cargo TOML version number and short VCS hash for disambiguation.
      projectVersion = cargoTOML: src: "${cargoTOML.package.version}+${builtins.substring 0 7 src.rev}";
      pkgsForSystem = system: import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
      };
      inherit (nixpkgs) lib;
      linuxSystems = (builtins.filter
        (platform: !(builtins.elem platform [
          "armv5tel-linux" # "error: missing bootstrap url for platform armv5te-unknown-linux-gnueabi"
          "mipsel-linux" # "error: attribute 'busybox' missing"
          "powerpc64-linux" # "error: evaluation aborted with the following error message: 'unsupported platform for the pure Linux stdenv'"
          "powerpc64le-linux" # Ditto
          "riscv32-linux" # "error: cannot coerce null to a string"
          "m68k-linux" # "error: cannot coerce null to a string"
          "s390x-linux" # Ditto
          "s390-linux" # Ditto
        ]))
        lib.platforms.linux);
    in
    (lib.recursiveUpdate
      (flake-utils.lib.eachSystem linuxSystems (system:
        let
          pkgs = pkgsForSystem system;
          lib = pkgs.lib;
        in
        {
          packages = {

            memflow-kvm =
              let
                src = inputs.memflow-kvm;
                cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/memflow-kvm/Cargo.toml")));
              in
              pkgs.rustPlatform.buildRustPackage (rec {
                pname = cargoTOML.package.name;
                version = projectVersion cargoTOML src;

                inherit src;

                RUST_BACKTRACE = "full";
                # memflow-kvm-ioctl has a custom build command that requires libclang to be found at the path specified by
                # the "LIBCLANG_PATH" environment variable: "thread 'main' panicked at 'Unable to find libclang" ...
                # "set the `LIBCLANG_PATH` environment variable to a path where one of these files can be found"
                LIBCLANG_PATH = "${pkgs.libclang.lib}/lib/";
                # Workarounds for bindgen being unable to find Linux & libc development headers
                # See: https://github.com/search?p=1&q=language%3Anix+BINDGEN_EXTRA_CLANG_ARGS&type=Code
                BINDGEN_EXTRA_CLANG_ARGS = lib.concatStringsSep " " [
                  "-I${pkgs.linuxHeaders}/include" # "fatal error: 'linux/types.h' file not found"
                  # "wrapper.h:2:10: fatal error: 'stddef.h' file not found"
                  "-isystem ${pkgs.llvmPackages.libclang.lib}/lib/clang/${lib.getVersion pkgs.clang}/include"
                  # "-isystem ${pkgs.llvmPackages.clang}/resource-root/include" # Also works
                ];

                cargoLock = {
                  lockFile = "${src}/Cargo.lock";
                };
                # Compile the KVM connector in the same way memflowup does to ensure it contains necessary exports
                cargoBuildFlags = [ "--workspace" "--all-features" ];

                meta = with cargoTOML.package; with lib; {
                  inherit description homepage;
                  downloadPage = https://github.com/memflow/memflow-kvm/releases;
                  license = licenses.mit;
                  platforms = platforms.linux;
                };
              });

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

              meta = {
                # See: https://github.com/memflow/memflow-kvm#licensing-note
                license = lib.licenses.gpl2Only;
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
            cglue-bindgen =
              let
                src = inputs.cglue-bindgen;
                cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/cglue-bindgen/Cargo.toml")));
              in
              pkgs.rustPlatform.buildRustPackage rec {
                pname = cargoTOML.package.name;
                version = projectVersion cargoTOML src;

                inherit src;

                cargoLock = {
                  lockFile = "${src}/Cargo.lock";
                };

                nativeBuildInputs = with pkgs; [ makeWrapper ];

                # cbindgen 0.20 (see: https://git.io/J9Gk2) & Rust nightly are needed for cglue-bindgen:
                # "ERROR: Parsing crate `memflow-ffi`: couldn't run `cargo rustc -Zunpretty=expanded`"
                # "error: the option `Z` is only accepted on the nightly compiler"
                postInstall = ''
                  wrapProgram $out/bin/cglue-bindgen \
                    --prefix PATH : ${lib.makeBinPath (with pkgs; [rust-cbindgen rust-bin.nightly.latest.default ])}
                '';

                meta = with cargoTOML.package; {
                  inherit description;
                  homepage = repository;
                  downloadPage = https://github.com/h33p/cglue/releases;
                  license = lib.licenses.mit;
                };
              };

            memflow =
              let
                src = inputs.memflow;
                cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/memflow/Cargo.toml")));
              in
              pkgs.rustPlatform.buildRustPackage rec {
                pname = cargoTOML.package.name;
                version = projectVersion cargoTOML src;

                inherit src;

                # Test suites are often failing for next branch commits since it's bleeding edge. Sometimes non-passing
                # commits include important fixes so we'll pin each package derivation to use a known working commit.
                doCheck = false;

                # Compile memflow with the lib/ path of each connector plugin
                MEMFLOW_EXTRA_PLUGIN_PATHS =
                  lib.concatStringsSep ";"
                    (builtins.map
                      (connector: "${connector}/lib/") # Turn each connector plugin package output into a lib/ path
                      (builtins.attrValues
                        (lib.attrsets.filterAttrs # Filter out package outputs that are not prefixed by "memflow-"
                          (name: _: lib.strings.hasPrefix "memflow-" name)
                          self.packages.${system})));

                nativeBuildInputs = with pkgs; [
                  self.packages.${system}.cglue-bindgen
                ];

                cargoLock = {
                  lockFile = "${src}/Cargo.lock";
                  outputHashes = {
                    "criterion-0.3.2" = "sha256-pCb+2DJEeNsHQ/gDUPyCSo0kvFpHW6Uwoz1JePyj68s=";
                  };
                };
                cargoBuildFlags = [ "--workspace" "--all-features" ];

                outputs = [ "out" "dev" ]; # Create outputs for the FFI shared library & development headers

                postBuild = ''
                  mkdir -vp $dev/include/
                  cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi \
                    -l C --output /dev/null || true
                  cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi \
                    -l C --output $dev/include/memflow.h
                  cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi \
                    -l C++ --output /dev/null || true
                  cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi \
                    -l C++ --output $dev/include/memflow_cpp.h
                '';

                postInstall = ''
                  mkdir -vp "$dev/lib/pkgconfig/"
                  cat << EOF > $dev/lib/pkgconfig/memflow-ffi.pc
                  libdir=$out/lib
                  includedir=$dev/include

                  Name: memflow-ffi
                  Description: C bindings for ${description}
                  Version: ${version}

                  Requires:
                  Cflags: -I\''${includedir}
                  Libs: -L\''${libdir} -lmemflow_ffi
                  EOF
                '';

                meta = with cargoTOML.package; {
                  inherit description homepage;
                  downloadPage = https://github.com/memflow/memflow/releases;
                  license = lib.licenses.mit;
                };
              };

            memflow-win32 = import ./pkgs/connectors/win32 { inherit inputs projectVersion pkgs lib; };
            memflow-qemu = import ./pkgs/connectors/qemu { inherit inputs projectVersion pkgs lib; };
            memflow-coredump = import ./pkgs/connectors/coredump { inherit inputs projectVersion pkgs lib; };
            memflow-native = import ./pkgs/connectors/native { inherit inputs projectVersion pkgs lib; };
            memflow-kcore = import ./pkgs/connectors/kcore { inherit inputs projectVersion pkgs lib; };

            cloudflow =
              let
                src = inputs.cloudflow;
                cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/cloudflow/Cargo.toml")));
              in
              pkgs.rustPlatform.buildRustPackage (rec {
                pname = cargoTOML.package.name;
                version = projectVersion cargoTOML src;

                inherit src;

                cargoLock = {
                  lockFile = "${src}/Cargo.lock";
                  outputHashes = {
                    "minidump-writer-0.1.0" = "sha256-tlwVlYQyAl5w7ObZLSzVBEqgiwFUUaioJOvbGCC6Jd4=";
                  };
                };
                cargoBuildFlags = [ "--workspace" "--all-features" ];

                nativeBuildInputs = with pkgs; [
                  pkg-config
                  makeWrapper
                ];
                buildInputs = with pkgs; [
                  fuse
                ];

                postInstall = lib.optionalString (builtins.elem system linuxSystems) (with pkgs; ''
                  wrapProgram $out/bin/cloudflow --prefix PATH : ${lib.makeBinPath [sudo]}
                '');

                meta = with cargoTOML.package; {
                  inherit description homepage;
                  downloadPage = https://github.com/memflow/cloudflow/releases;
                  license = lib.licenses.mit;
                };
              });

            scanflow =
              let
                src = inputs.scanflow;
                cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/scanflow/Cargo.toml")));
              in
              pkgs.rustPlatform.buildRustPackage (rec {
                pname = cargoTOML.package.name;
                version = projectVersion cargoTOML src;

                inherit src;

                cargoLock = {
                  lockFile = "${src}/Cargo.lock";
                };
                cargoBuildFlags = [ "--all-features" ];

                meta = with cargoTOML.package; {
                  inherit description homepage;
                  downloadPage = https://github.com/memflow/scanflow/releases;
                  license = lib.licenses.mit;
                };
              });

          };
        }
      ))) // {
      nixosModule = { config, pkgs, lib, ... }:
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
}
