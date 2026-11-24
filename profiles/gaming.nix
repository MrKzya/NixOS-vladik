{ config, pkgs, ... }:

{
  imports = [ ../modules/desktop/shared.nix ];

  system.nixos.tags = [ "Gaming" ];
  boot.loader.grub.configurationName = "Gaming";
  services.desktopManager.plasma6.enable = true;
  services.displayManager.defaultSession = "plasma";

  programs = {
    steam.enable = true;
    gamemode.enable = true;
  };
  services.pipewire.alsa.support32Bit = true;

  environment = {
    systemPackages = with pkgs; [ kitty mangohud ];
    etc."xdg/kcminputrc".text = ''
      [Mouse]
      cursorTheme=macOS
      cursorSize=${toString config.mySystem.cursor.size}
    '';
  };
}
