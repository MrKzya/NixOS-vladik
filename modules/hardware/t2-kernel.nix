{ config, inputs, lib, pkgs, ... }:
let
  buildPkgs = import inputs.t2-kernel-nixpkgs { system = "x86_64-linux"; };
  kernel = buildPkgs.callPackage (inputs.t2-kernel-hardware + "/apple/t2/pkgs/linux-t2") { };
in
{
  # Preserve the main Nixpkgs package set for userspace and the NixOS module ABI.
  # This release includes apple-bce in-tree. Keep the upstream T2 initrd settings.
  assertions = [{
    assertion = config.hardware.apple-t2.kernelChannel == "stable";
    message = "The cached T2 Live kernel is pinned to stable; validate a new kernel and its artifacts before changing channels.";
  }];
  boot.kernelPackages = lib.mkOverride 90 (pkgs.linuxPackagesFor kernel);
}
