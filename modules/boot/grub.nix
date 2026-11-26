{ config, inputs, lib, pkgs, ... }:

let
  cfg = config.mySystem.grub;
  minegrub = cfg.theme == "minegrub";
  theme = pkgs.runCommand "minegrub-nixos-theme" {
    nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pillow ])) ];
  } ''
    cp -R ${inputs.minegrub}/minegrub theme
    chmod -R u+w theme
    sed -i '/^    update_background(bg_file)$/d; /^    update_package_count()$/d' theme/update_theme.py
    python theme/update_theme.py "" "I use NixOS BTW!"
    python - <<'PY'
    from PIL import Image

    path = "theme/logo.png"
    logo = Image.open(path).convert("RGBA")
    logo = logo.crop(logo.getbbox())
    logo.thumbnail((720, 195), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (720, logo.height))
    canvas.paste(logo, ((720 - logo.width) // 2, 0))
    canvas.save(path)
    PY
    mkdir -p "$out"
    cp theme/*.png theme/*.pf2 "$out/"
    cp ${./minegrub/theme.txt} "$out/theme.txt"
  '';
in
{
  imports = [
    inputs.minegrub.nixosModules.default
    inputs.minegrub-world.nixosModules.default
  ];

  options.mySystem.grub = {
    theme = lib.mkOption {
      type = lib.types.enum [ "minegrub" "world-selection" "none" ];
      default = "minegrub";
      description = "Тема меню GRUB.";
    };
    efiVideoMode = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional GOP mode list for Minegrub under EFI.";
    };
  };

  config = lib.mkMerge [
    {
      boot.loader = {
        efi.canTouchEfiVariables = lib.mkDefault false;
        grub = {
          enable = true;
          configurationLimit = lib.mkDefault (if minegrub then 0 else 20);
          useOSProber = lib.mkDefault false;
          minegrub-world-sel.enable = cfg.theme == "world-selection";
        };
      };
    }
    (lib.mkIf minegrub {
      boot.loader.grub = {
        theme = "${theme}";
        splashImage = "${theme}/background.png";
        gfxmodeEfi = lib.mkIf (cfg.efiVideoMode != null) cfg.efiVideoMode;
      };

      # Limit the patch to the pinned NixOS GRUB generator. It runs before files
      # reach the ESP and leaves entry order, IDs, kernels and rollback to NixOS.
      nixpkgs.overlays = [(final: prev: {
        replaceVars = src: replacements:
          let zone = lib.optionalString (config.time.timeZone != null)
            ":${prev.tzdata}/share/zoneinfo/${config.time.timeZone}";
          in if lib.hasSuffix "/nixos/modules/system/boot/loader/grub/install-grub.pl" (toString src) then
            prev.replaceVarsWith {
              inherit src replacements;
              preBuild = ''
                cp "$src" install-grub.pl
                chmod u+w install-grub.pl
                ${prev.patch}/bin/patch --batch --fuzz=0 install-grub.pl < ${./minegrub/generations.patch}
                substituteInPlace install-grub.pl \
                  --replace-fail __NIXOS_VLADIK_GENERATION_LABELS__ ${./minegrub/generation-labels.pl} \
                  --replace-fail __NIXOS_VLADIK_SYSTEM_TZ__ ${lib.escapeShellArg zone}
                src="$PWD/install-grub.pl"
              '';
            }
          else prev.replaceVars src replacements;
      })];
    })
  ];
}
