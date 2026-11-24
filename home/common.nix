{ config, lib, pkgs, ... }:

{
  home.stateVersion = "26.05";
  xdg.enable = true;

  home.packages = with pkgs; [ starship fastfetch ];

  xdg.configFile."fish/config.fish".source = ../configs/fish/config.fish;

  # fishd owns this file and can change it at runtime.
  home.activation.seedFish = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.bash}/bin/bash ${../scripts/seed-config.sh} \
      ${../configs/fish/fish_variables} ${lib.escapeShellArg "${config.xdg.configHome}/fish/fish_variables"}
  '';
}
