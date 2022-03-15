{ inputs, pkgs, lib, projectVersion }:

let
  src = inputs.memflow-kvm;
  cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/memflow-kvm/Cargo.toml")));
in
pkgs.rustPlatform.buildRustPackage (rec {
  pname = cargoTOML.package.name;
  version = projectVersion cargoTOML src;

  inherit src;

  RUST_BACKTRACE = "full";
  # memflow-kvm-ioctl has a custom build command that requires libclang to be found at the path specified by
  # the "LIBCLANG_PATH" environment variable: "thread 'main' panicked at 'Unable to find libclang" ...
  # "set the `LIBCLANG_PATH` environment variable to a path where one of these files can be found"
  LIBCLANG_PATH = "${pkgs.libclang.lib}/lib/";
  # Workarounds for bindgen being unable to find Linux & libc development headers
  # See: https://github.com/search?p=1&q=language%3Anix+BINDGEN_EXTRA_CLANG_ARGS&type=Code
  BINDGEN_EXTRA_CLANG_ARGS = lib.concatStringsSep " " [
    "-I${pkgs.linuxHeaders}/include" # "fatal error: 'linux/types.h' file not found"
    # "wrapper.h:2:10: fatal error: 'stddef.h' file not found"
    "-isystem ${pkgs.llvmPackages.libclang.lib}/lib/clang/${lib.getVersion pkgs.clang}/include"
    # "-isystem ${pkgs.llvmPackages.clang}/resource-root/include" # Also works
  ];

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };
  # Compile the KVM connector in the same way memflowup does to ensure it contains necessary exports
  cargoBuildFlags = [ "--workspace" "--all-features" ];

  meta = with cargoTOML.package; with lib; {
    inherit description homepage;
    downloadPage = https://github.com/memflow/memflow-kvm/releases;
    license = licenses.mit;
    platforms = platforms.linux;
  };
})
