{ config, inputs, lib, ... }:

{
  imports = [
    inputs.nixos-hardware.nixosModules.apple-t2
    inputs.t2fanrd.nixosModules.t2fanrd
  ];

  hardware.apple-t2 = {
    kernelChannel = lib.mkDefault "stable";
    firmware.enable = lib.mkDefault false;
    enableIGPU = lib.mkDefault false;
  };

  hardware.apple.touchBar.enable = lib.mkDefault false;
  services.t2fanrd.enable = lib.mkDefault false;
  networking.networkmanager.wifi.backend = lib.mkDefault "iwd";
}
