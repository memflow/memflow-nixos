## Example

```nix
{
  inputs = {
    memflow.url = github:memflow/memflow-nixos;
  };

  outputs = { self, nixpkgs, flake-utils, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in
      {
        devShell = pkgs.mkShell {
          nativeBuildInputs = with pkgs; with inputs.memflow; [
            memflow # Memflow FFI
          ];
        };
      }
    );
}
```
