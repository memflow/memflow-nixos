{ self, inputs, pkgs, lib, projectVersion, description, system }:

let
  src = inputs.memflow;
  cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/memflow/Cargo.toml")));
in
pkgs.rustPlatform.buildRustPackage rec {
  pname = cargoTOML.package.name;
  version = projectVersion cargoTOML src;

  inherit src;

  # Test suites are often failing for next branch commits since it's bleeding edge. Sometimes non-passing
  # commits include important fixes so we'll pin each package derivation to use a known working commit.
  doCheck = false;

  # Compile memflow with the lib/ path of each connector plugin
  MEMFLOW_EXTRA_PLUGIN_PATHS =
    lib.concatStringsSep ":"
      (builtins.map
        (connector: "${connector}/lib/") # Turn each connector plugin package output into a lib/ path
        (builtins.attrValues
          (lib.attrsets.filterAttrs # Filter out package outputs that are not prefixed by "memflow-"
            (name: _: lib.strings.hasPrefix "memflow-" name)
            self.packages.${system})));

  nativeBuildInputs = with pkgs; [
    self.packages.${system}.cglue-bindgen
  ];

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      "criterion-0.3.2" = "sha256-pCb+2DJEeNsHQ/gDUPyCSo0kvFpHW6Uwoz1JePyj68s=";
    };
  };
  cargoBuildFlags = [ "--workspace" "--all-features" ];

  outputs = [ "out" "dev" ]; # Create outputs for the FFI shared library & development headers

  postBuild = ''
    mkdir -vp $dev/include/
    cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi \
      -l C --output /dev/null || true
    cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi \
      -l C --output $dev/include/memflow.h
    cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi \
      -l C++ --output /dev/null || true
    cglue-bindgen -c memflow-ffi/cglue.toml -- --config memflow-ffi/cbindgen.toml --crate memflow-ffi \
      -l C++ --output $dev/include/memflow_cpp.h
  '';

  postInstall = ''
    mkdir -vp "$dev/lib/pkgconfig/"
    cat << EOF > $dev/lib/pkgconfig/memflow-ffi.pc
    libdir=$out/lib
    includedir=$dev/include

    Name: memflow-ffi
    Description: C bindings for ${description}
    Version: ${version}

    Requires:
    Cflags: -I\''${includedir}
    Libs: -L\''${libdir} -lmemflow_ffi
    EOF
  '';

  meta = with cargoTOML.package; {
    inherit description homepage;
    downloadPage = https://github.com/memflow/memflow/releases;
    license = lib.licenses.mit;
  };
}
