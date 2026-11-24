{ lib, ... }:

{
  # Copy the installed guest's generated hardware module to this ignored file.
  # Use a path: flake reference so Nix reads the local copy.
  imports = lib.optional (builtins.pathExists ./hardware-configuration.local.nix)
    ./hardware-configuration.local.nix;
}
