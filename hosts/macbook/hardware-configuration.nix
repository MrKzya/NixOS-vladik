{ lib, ... }:

{
  # Generate on the Intel MacBook T2. Populate the ignored .local.nix file
  # with the real root and dedicated Linux ESP mounted at /boot.
  imports = lib.optional (builtins.pathExists ./hardware-configuration.local.nix)
    ./hardware-configuration.local.nix;
}
