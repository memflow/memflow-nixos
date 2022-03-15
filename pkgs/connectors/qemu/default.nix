{ inputs, pkgs, lib, projectVersion }:

let
  src = inputs.memflow-qemu;
  cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml")));
in
pkgs.rustPlatform.buildRustPackage (rec {
  pname = cargoTOML.package.name;
  version = projectVersion cargoTOML src;

  inherit src;

  doCheck = false;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };
  # See: https://github.com/memflow/memflow-qemu/tree/next#building-the-stand-alone-connector-for-dynamic-loading
  cargoBuildFlags = [ "--workspace" "--all-features" ];

  meta = with cargoTOML.package; {
    inherit description homepage;
    downloadPage = https://github.com/memflow/memflow-qemu/releases;
    license = lib.licenses.mit;
  };
})
