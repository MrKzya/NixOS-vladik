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

  # Breeze looks up its default wallpaper package by the name "Next".
  home-manager.sharedModules = [
    ({ config, ... }: {
      xdg.dataFile = {
        "wallpapers/Next/metadata.json".text = builtins.toJSON {
          KPlugin = { Id = "Next"; Name = "Oboi"; };
        };
        "wallpapers/Next/contents/images/1920x1200.jpg".source =
          config.xdg.dataFile."wallpapers/Oboi.jpg".source;
      };
    })
  ];

  environment = {
    systemPackages = with pkgs; [ kitty mangohud ];
    etc."xdg/kcminputrc".text = ''
      [Mouse]
      cursorTheme=macOS
      cursorSize=${toString config.mySystem.cursor.size}
    '';
  };
}
