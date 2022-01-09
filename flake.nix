{
  description = "memflow physical memory introspection framework";

  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    rust-overlay.url = github:oxalica/rust-overlay;
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
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
            text = with self.packages.${system}; ''
              Name: memflow-ffi
              Description: C bindings for the memflow physical memory introspection framework
              Version: ${memflow.version}

              Requires:
              Libs: -L${memflow}/lib -l:libmemflow_ffi.a
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
                rev = "9461991d83937859a76648339c0587735f6d64ee";
                sha256 = "sha256-nHNtWjswYWnzYOQ6v86ApvcvhY3XiAwAQJINax2nbzw=";
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

              cargoHash = "sha256-Mj23+M4ws+ZfaDop0QisTLCMjtTftgrQDr3cQNNSvXc=";
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              outputs = [ "out" "dev" ]; # Create outputs for the FFI shared library & development headers

              postBuild = ''
                mkdir -p $dev/include
                cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi -l C --output /dev/null || true
                cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi -l C --output $dev/include/memflow.h
                cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi -l C++ --output /dev/null || true
                cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi -l C++ --output $dev/include/memflow_cpp.h
              '';

              meta = with lib; with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow/releases;
                license = licenses.mit;
              };
            };

          memflow-win32 =
            let
              src = pkgs.fetchFromGitHub {
                owner = "memflow";
                repo = "memflow-win32";
                rev = "806ffe08c54b17bd8365ac5fb1fefe515d760130";
                # See: https://github.com/memflow/memflow-win32/commits/main
                sha256 = "sha256-Gy4ZWXyGzU8442Jo+pH6GajWig7EnWwNdrOAX7cPHY0=";
              };
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage (rec {
              pname = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              cargoHash = "sha256-RpWWGKiCM9WgxIth+BmwZ+HB5YYnR6Ilos/nVp04IAU=";
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              meta = with lib; with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow-win32/releases;
                license = licenses.mit;
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
              name = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              RUST_BACKTRACE = "full";
              LIBCLANG_PATH = "${pkgs.libclang.lib}/lib/"; # "thread 'main' panicked at 'Unable to find libclang"

              cargoHash = "sha256-QbdxPdLMBAmDho3j0M2dWFhJjYaa2TyREAY4Wec5nz4=";
              # Compile the KVM connector in the same way memflowup does to ensure it contains necessary exports
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              buildInputs = with pkgs; [
                llvmPackages.libclang
              ];
              nativeBuildInputs = with pkgs; [
                # FIXME: not sure what the correct package to use here is?
                rust-bindgen # "./mabi.h:14:10: fatal error: 'linux/types.h' file not found"
              ];

              meta = with lib; with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow-kvm/releases;
                license = licenses.mit;
              };
            });

          memflow-qemu =
            let
              src = pkgs.fetchFromGitHub {
                owner = "memflow";
                repo = "memflow-qemu";
                # See: https://github.com/memflow/memflow-qemu/tree/next
                rev = "1b6ab1ff69188b800f9c02c63cd2c0cd86796125";
                sha256 = "sha256-DpGdPTckq8wH/5R0kKOZbz+piRSX/5yzdFOchck1Xmw=";
                fetchSubmodules = true;
              };
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage (rec {
              name = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              doCheck = false;

              cargoHash = "sha256-8Ba0utfeA2uKeB+SfSZPwusxiFGtRF3VmoO9+6CZ0O8=";
              # See: https://github.com/memflow/memflow-qemu/tree/next#building-the-stand-alone-connector-for-dynamic-loading
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              meta = with lib; with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow-qemu/releases;
                license = licenses.mit;
              };
            });
        };

        memflow-kmod = with pkgs;
        let 
          kvm = self.packages.${system}.memflow-kvm;
        in
          { kernel }:
          stdenv.mkDerivation {
            pname = "memflow-kmod-${kvm.version}-${kvm.kernel.version}";
            inherit (kvm) version src;

            preBuild = ''
              sed -e "s@/lib/modules/\$(.*)@${kernel.dev}/lib/modules/${kernel.modDirVersion}@" -i Makefile
            '';
            installPhase = ''
              install -D build/memflow.ko -t $out/lib/modules/${kernel.modDirVersion}/misc/
            '';
            dontStrip = true;
            hardeningDisable = [ "format" "pic" ];
            kernel = kernel.dev;
            nativeBuildInputs = kernel.moduleBuildDependencies;
            meta = with lib; {
              # See: https://github.com/memflow/memflow-kvm#licensing-note
              license = with licenses; [ gpl2Only ];
            };
          };
      }
    );
}
