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
      "unicorn-engine-2.0.0-rc6" = "sha256-mbEu81okyTYdBzieC3thyE0fqfjxgpmBPOkOvE5ODFE=";
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
