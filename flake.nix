{
  description = "memflow physical memory introspection framework";

  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    rust-overlay.url = github:oxalica/rust-overlay;
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
                Description: C bindings for the memflow physical memory introspection framework
                Version: ${memflow.version}

                Requires:
                Libs: -L${staticOnly}/lib -lmemflow_ffi
                Cflags: -I${memflow.dev}/include
              '';
          };

          cglue-bindgen =
            let
              src = pkgs.fetchFromGitHub {
                owner = "h33p";
                repo = "cglue";
                # See: https://github.com/h33p/cglue/commits/main
                rev = "d85d2e83bd6f5eb6331174fbdc322418031f051b";
                sha256 = "sha256-S8c1+eado9Ov91OHN8XSqxBsixERJHZ3ZEtDmMYgyLY=";
              };
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/cglue-bindgen/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage rec {
              pname = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              cargoHash = "sha256-RyOwoope/r9kU1tqbAUUnpBPUM+t+R1syj7CnwBE2G8=";

              nativeBuildInputs = with pkgs; [ makeWrapper ];

              # cbindgen 0.20 (see: https://git.io/J9Gk2) & Rust nightly are needed for cglue-bindgen:
              #   "ERROR: Parsing crate `memflow-ffi`: couldn't run `cargo rustc -Zunpretty=expanded`"
              #   "error: the option `Z` is only accepted on the nightly compiler"
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
              src = pkgs.fetchFromGitHub {
                owner = "memflow";
                repo = "memflow";
                # See: https://github.com/memflow/memflow/commits/next
                rev = "f43d70d7e33c8745d26cfc0d18cf4654ec4083ce";
                sha256 = "sha256-Ni/C8TQHC6hvsqu4tj2nHQYEDcn+0ssLQ0h94OozUew=";
              };
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

              cargoHash = "sha256-IkT9dxTzfIcVaBspwUSNo6NYvwxJqHmt+bUDvAwpgu8=";
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
              src = pkgs.fetchFromGitHub {
                owner = "memflow";
                repo = "memflow-win32";
                rev = "2788d9371ddc6f353883d9df8c2456446784d080";
                # See: https://github.com/memflow/memflow-win32/commits/main
                sha256 = "sha256-nMcAdH39favxjQOhP5V6GX7zbzQlUH0LJ4OqmHFjDcA=";
              };
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage (rec {
              pname = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              cargoHash = "sha256-tcXIUV2EHVdFXq8hK1GBndrh3ZzGEF6+x2u6MRE98pQ=";
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              meta = with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow-win32/releases;
                license = lib.licenses.mit;
              };
            });

          memflow-kvm =
            let
              src = pkgs.fetchFromGitHub {
                owner = "memflow";
                repo = "memflow-kvm";
                # See: https://github.com/memflow/memflow-kvm/commits/next
                rev = "1c2875522fbe4d29df61d23e69233debabf8f198";
                sha256 = "sha256-Nashl1rt5iobmD5w+E4Ct1/FYzwGkSw2eYgSNbTRix0=";
                fetchSubmodules = true;
              };
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
              src = pkgs.fetchFromGitHub {
                owner = "memflow";
                repo = "memflow-qemu";
                # See: https://github.com/memflow/memflow-qemu/commits/next
                rev = "1b6ab1ff69188b800f9c02c63cd2c0cd86796125";
                sha256 = "sha256-DpGdPTckq8wH/5R0kKOZbz+piRSX/5yzdFOchck1Xmw=";
                fetchSubmodules = true;
              };
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
            };
          };
      }
    )) //
    {
      nixosModule = { config, pkgs, lib, ... }:
        let
          cfg = config.memflow;
        in
        {
          options.memflow = with lib; {
            kvm.enable = mkEnableOption "Whether to enable memflow memory introspection framework for KVM";

            kvm.loadModule = mkOption {
              default = true;
              type = types.bool;
              description = "Automatically load the memflow KVM kernel module on boot";
            };

            kvm.kernelPatch = mkOption {
              default = true;
              type = types.bool;
              description = "Kernel configuration that enables KALLSYMS_ALL";
            };
          };

          config = with lib; mkIf cfg.kvm.enable {
            boot.kernelPatches = mkIf cfg.kvm.kernelPatch [
              {
                name = "memflow-enable-kallsyms-all";
                patch = null;
                extraConfig = ''
                  KALLSYMS_ALL y
                '';
              }
            ];

            system.requiredKernelConfig = with config.lib.kernelConfig; [
              (isYes "KALLSYMS_ALL")
            ];

            boot.kernelModules = mkIf cfg.kvm.loadModule [ "memflow" ];
            boot.extraModulePackages = [ (self.memflow-kmod.${pkgs.system} config.boot.kernelPackages.kernel) ];
          };
        };
    };
}
