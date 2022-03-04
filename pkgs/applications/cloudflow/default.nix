{ inputs, pkgs, lib, projectVersion, system, linuxSystems }:

let
  src = inputs.cloudflow;
  cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/cloudflow/Cargo.toml")));
in
pkgs.rustPlatform.buildRustPackage (rec {
  pname = cargoTOML.package.name;
  version = projectVersion cargoTOML src;

  inherit src;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      "minidump-writer-0.1.0" = "sha256-tlwVlYQyAl5w7ObZLSzVBEqgiwFUUaioJOvbGCC6Jd4=";
    };
  };
  cargoBuildFlags = [ "--workspace" "--all-features" ];

  nativeBuildInputs = with pkgs; [
    pkg-config
    makeWrapper
  ];
  buildInputs = with pkgs; [
    fuse
  ];

  postInstall = lib.optionalString (builtins.elem system linuxSystems) (with pkgs; ''
    wrapProgram $out/bin/cloudflow --prefix PATH : ${lib.makeBinPath [sudo]}
  '');

  meta = with cargoTOML.package; {
    inherit description homepage;
    downloadPage = https://github.com/memflow/cloudflow/releases;
    license = lib.licenses.mit;
  };
})
