## Example

```nix
{
  inputs = {
    zig-overlay.url = github:arqv/zig-overlay;
    memflow.url = github:weewoo22/memflow-nixos;
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        lib = pkgs.lib;

        # Collect overridden package outputs into this variable
        memflowPkgs = builtins.mapAttrs
          (name: package:
            (package.overrideAttrs
              (super: {
                # dontStrip = true;
                # buildType = "debug";
              })
            )
          )
          inputs.memflow.packages.${system};
      in
      {
        defaultPackage = pkgs.mkShell {
          MEMFLOW_CONNECTOR_INVENTORY_PATHS = with memflowPkgs; lib.concatStringsSep ";" [
            # Memflow connector plugins
            "${memflow-kvm}/lib/" # KVM Connector
            "${memflow-win32}/lib/" # Win32 Connector plugin
            # etc...
          ];
          nativeBuildInputs = with pkgs; with memflowPkgs; [
            memflow # Memflow FFI
          ];
        };
      }
    );
}
```
