{ inputs, pkgs, lib, projectVersion }:

let
  src = inputs.scanflow;
  cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/scanflow/Cargo.toml")));
in
pkgs.rustPlatform.buildRustPackage (rec {
  pname = cargoTOML.package.name;
  version = projectVersion cargoTOML src;

  inherit src;

  doCheck = false;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };
  cargoBuildFlags = [ "--all-features" ];

  meta = with cargoTOML.package; {
    inherit description homepage;
    downloadPage = https://github.com/memflow/scanflow/releases;
    license = lib.licenses.mit;
    mainProgram = "scanflow-cli";
    broken = true;
  };
})
