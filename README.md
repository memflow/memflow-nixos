# Packaging for Nix(OS)

## Examples

### FFI Project

To create an FFI project include the `memflow` output from this Flake in your development environment shell. All connector plugins are available by default.

```nix
{
  inputs = {
    memflow.url = github:memflow/memflow-nixos;
  };

  outputs = { self, nixpkgs, flake-utils, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; with inputs.memflow; [
            memflow # Memflow FFI
          ];
        };
      }
    );
}
```

If you'd like to read the FFI header definitions run `pkg-config --cflags-only-I memflow-ffi` to get their locations.

### NixOS System Module

To install the kernel module for the KVM connector plugin on your system simply install the NixOS module that this Flake provides:

```nix
# flake.nix
{
  inputs.memflow.url = github:memflow/memflow-nixos;

  outputs = { self, nixpkgs, memflow, ... }: {
    nixosConfigurations = {
      my-system = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ memflow.nixosModule ];
      };
    };
  };
}
```
```nix
# configuration.nix
{ ... }:
{
  memflow.kvm.enable = true;
}
```
