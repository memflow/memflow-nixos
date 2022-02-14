rec {
  description = "memflow physical memory introspection framework";

  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    rust-overlay.url = github:oxalica/rust-overlay;

    cglue-bindgen = {
      url = github:h33p/cglue;
      flake = false;
    };
    memflow = {
      url = github:memflow/memflow/next;
      flake = false;
    };
    memflow-win32 = {
      url = github:memflow/memflow-win32;
      flake = false;
    };
    memflow-kvm = {
      url = github:memflow/memflow-kvm/next;
      flake = false;
    };
    memflow-qemu = {
      url = github:memflow/memflow-qemu/next;
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, ... } @ inputs:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };
        lib = pkgs.lib;

        # Function that creates the package derivation version string from the Cargo TOML version & git rev hash.
        # I'm including both the Cargo TOML version number and short VCS hash for disambiguation.
        projectVersion = cargoTOML: src: "${cargoTOML.package.version}+${builtins.substring 0 7 src.rev}";
      in
      {
        packages = {
          pkg-config-file = pkgs.writeTextFile {
            name = "memflow-ffi";
            destination = "/share/pkgconfig/memflow-ffi.pc";
            text = with self.packages.${system};
              let
                # for some reason -l:libmemflow-ffi.a doesn't work
                staticOnly = pkgs.runCommand "memflow-static" { } ''
                  mkdir -p $out/lib
                  ln -s ${memflow}/lib/libmemflow_ffi.a $out/lib
                '';
              in
              ''
                Name: memflow-ffi
                Description: C bindings for ${description}
                Version: ${memflow.version}

                Requires:
                Libs: -L${staticOnly}/lib -lmemflow_ffi
                Cflags: -I${memflow.dev}/include
              '';
          };

          cglue-bindgen =
            let
              src = inputs.cglue-bindgen;
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/cglue-bindgen/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage rec {
              pname = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              cargoHash = "sha256-cpL/55qsdwBKcJALEX5AFAGf2Zkli8yCqw/bS18zRGU=";

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

              nativeBuildInputs = with pkgs; [
                self.packages.${system}.cglue-bindgen
              ];

              cargoHash = "sha256-fmKoaanbJ2eo6tdAcqBB8K+i3QKSuh21Vx8WOy1I+8Y=";
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

              meta = with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow/releases;
                license = lib.licenses.mit;
              };
            };

          memflow-win32 =
            let
              src = inputs.memflow-win32;
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage (rec {
              pname = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              cargoHash = "sha256-t+1ZPxiU8rsJw7qNkGuvpY1nEDYjJ7U11qZOj8Ofs5A=";
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              meta = with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow-win32/releases;
                license = lib.licenses.mit;
              };
            });

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
              LIBCLANG_PATH = "${pkgs.libclang.lib}/lib/"; # "thread 'main' panicked at 'Unable to find libclang"

              cargoHash = "sha256-3mEjoaC6GHwilg/iswHOUpYPAtZtY5PJnnF9sOE2tMw=";
              # Compile the KVM connector in the same way memflowup does to ensure it contains necessary exports
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              buildInputs = with pkgs; [
                llvmPackages.libclang
              ];
              nativeBuildInputs = with pkgs; [
                # FIXME: not sure what the correct package to use here is?
                rust-bindgen # "./mabi.h:14:10: fatal error: 'linux/types.h' file not found"
              ];

              meta = with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow-kvm/releases;
                license = lib.licenses.mit;
              };
            });

          memflow-qemu =
            let
              src = inputs.memflow-qemu;
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage (rec {
              pname = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              doCheck = false;

              cargoHash = "sha256-tG1SVXvydVAsyuZvLlh6FM8skdgKojSAyk6QdSZ0fLY=";
              # See: https://github.com/memflow/memflow-qemu/tree/next#building-the-stand-alone-connector-for-dynamic-loading
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              meta = with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow-qemu/releases;
                license = lib.licenses.mit;
              };
            });
        };

        memflow-kmod = with pkgs;
          let
            memflow-kvm = self.packages.${system}.memflow-kvm;
          in
          kernel: stdenv.mkDerivation {
            name = "memflow-kmod-${memflow-kvm.version}-${kernel.version}";
            inherit (memflow-kvm) version;
            src = builtins.fetchGit {
              url = https://github.com/memflow/memflow-kvm.git;
              ref = "next";
              inherit (inputs.memflow-kvm) rev;
              submodules = true;
            };

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
            };
          };
      }
    )) // {
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
