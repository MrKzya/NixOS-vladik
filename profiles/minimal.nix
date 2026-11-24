{ ... }:

{
  system.nixos.tags = [ "Minimal" ];
  boot.loader.grub.configurationName = "Minimal";
  systemd.defaultUnit = "multi-user.target";
}
