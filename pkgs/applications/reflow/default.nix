{ inputs, pkgs, lib, projectVersion, description }:

let
  src = inputs.reflow;
  cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml")));
in
pkgs.rustPlatform.buildRustPackage (rec {
  pname = cargoTOML.package.name;
  version = projectVersion cargoTOML src;

  inherit src;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      "memflow-0.1.5" = "sha256-JT1Igi7IwrtKstkDfeXT3rqVIsLBpPaW1TBzKRl5Yho=";
    };
  };
  cargoBuildFlags = [ "--all-features" ];

  nativeBuildInputs = with pkgs; [
    pkg-config
  ];
  buildInputs = with pkgs; [
    unicorn
  ];

  meta = with cargoTOML.package;{
    inherit description homepage;
    downloadPage = https://github.com/memflow/reflow/releases;
    license = lib.licenses.mit;
    broken = true;
  };
})
