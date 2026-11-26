{ config, lib, ... }:

{
  config = lib.mkIf config.mySystem.desktop.plasma.enable {
    services.desktopManager.plasma6.enable = true;

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

    environment.etc."xdg/kcminputrc".text = ''
      [Mouse]
      cursorTheme=macOS
      cursorSize=${toString config.mySystem.cursor.size}
    '';
    environment.etc."xdg/kxkbrc".text = ''
      [Layout]
      Use=true
      LayoutList=us,ru
      ResetOldOptions=true
      Options=grp:alt_shift_toggle
    '';
  };
}
