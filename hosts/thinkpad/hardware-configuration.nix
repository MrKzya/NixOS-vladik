{ lib, ... }:

{
  # Keep the generated root, ESP, swap and initrd settings in the ignored module.
  imports = lib.optional (builtins.pathExists ./hardware-configuration.local.nix)
    ./hardware-configuration.local.nix;
}
