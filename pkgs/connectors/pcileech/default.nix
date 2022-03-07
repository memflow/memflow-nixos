{ inputs, pkgs, lib, projectVersion }:

let
  src = inputs.memflow-pcileech;
  cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/memflow-pcileech/Cargo.toml")));
in
pkgs.rustPlatform.buildRustPackage (rec {
  pname = cargoTOML.package.name;
  version = projectVersion cargoTOML src;

  inherit src;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };
  cargoBuildFlags = [ "--all-features" ];

  LIBCLANG_PATH = "${pkgs.libclang.lib}/lib/";
  BINDGEN_EXTRA_CLANG_ARGS = lib.concatStringsSep " " [
    # "fatal error: 'inttypes.h' file not found"
    # "-isystem ${pkgs.llvmPackages.libclang.lib}/lib/clang/${lib.getVersion pkgs.clang}/include"
    # "-I${pkgs.linuxHeaders}/include"
    "-I${pkgs.clang}/resource-root/include"
  ];

  nativeBuildInputs = with pkgs; [
    pkg-config
  ];
  buildInputs = with pkgs; [
    libusb1
    llvmPackages.libclang.lib
  ];

  meta = with cargoTOML.package; {
    inherit description homepage;
    downloadPage = https://github.com/memflow/memflow-pcileech/releases;
    # See: https://github.com/memflow/memflow-pcileech#license
    license = lib.licenses.gpl3Only;
  };
})
