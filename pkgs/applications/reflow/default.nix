{ inputs, pkgs, lib, projectVersion, description }:

let
  src = inputs.reflow;
  cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml")));
in
pkgs.rustPlatform.buildRustPackage (rec {
  pname = cargoTOML.package.name;
  version = projectVersion cargoTOML src;

  inherit src;

  cargoHash = "sha256-J0AvUC0kvRJ9LLG+p5r5D/OVLoJwl0xI3rT2N36o7iQ=";
  cargoBuildFlags = [ "--all-features" ];

  nativeBuildInputs = with pkgs; [
    pkg-config
  ];
  buildInputs = with pkgs; [
    unicorn
    openssl
  ];

  meta = with cargoTOML.package;{
    inherit description homepage;
    downloadPage = https://github.com/memflow/reflow/releases;
    license = lib.licenses.mit;
  };
})
