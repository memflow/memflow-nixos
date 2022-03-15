{ inputs, pkgs, lib, projectVersion }:

let
  src = inputs.memflow-native;
  cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml")));
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
    downloadPage = https://github.com/memflow/memflow-native/releases;
    license = lib.licenses.mit;
  };
})
