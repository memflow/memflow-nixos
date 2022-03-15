{ inputs, pkgs, lib, projectVersion }:

let
  src = inputs.cglue-bindgen;
  cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/cglue-bindgen/Cargo.toml")));
in
pkgs.rustPlatform.buildRustPackage rec {
  pname = cargoTOML.package.name;
  version = projectVersion cargoTOML src;

  inherit src;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };

  nativeBuildInputs = with pkgs; [ makeWrapper ];

  # cbindgen 0.20 (see: https://git.io/J9Gk2) & Rust nightly are needed for cglue-bindgen:
  # "ERROR: Parsing crate `memflow-ffi`: couldn't run `cargo rustc -Zunpretty=expanded`"
  # "error: the option `Z` is only accepted on the nightly compiler"
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
}
