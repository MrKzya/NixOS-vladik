{ config, hostDir, inputs, lib, pkgs, ... }:

let
  cfg = config.mySystem.macbook;
  cache = import ./t2-cache.nix;
  grub = config.boot.loader.grub;
  efi = config.boot.loader.efi;
  esp = config.fileSystems."/boot" or { };
  firmwareDir = hostDir + "/firmware";
  isPartition = device: device != null &&
    builtins.match "/dev/disk/by-partuuid/[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}" device != null;
in
{
  imports = [
    ./t2-kernel.nix
    inputs.nixos-hardware.nixosModules.apple-t2
    inputs.t2fanrd.nixosModules.t2fanrd
  ];

  options.mySystem.macbook = {
    linuxEsp = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Confirmed Linux ESP /dev/disk/by-partuuid/... (local module only).";
    };
    macosEsp = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Existing macOS ESP /dev/disk/by-partuuid/... (local module only).";
    };
    localFirmware.enable = lib.mkEnableOption "local Broadcom firmware from hosts/macbook/firmware/brcm";
    intelMedia.enable = lib.mkEnableOption "Intel VA-API media driver";
  };

  config = {
    nix.settings = {
      extra-substituters = [ cache.url ];
      extra-trusted-public-keys = [ cache.key ];
    };

    networking.networkmanager.wifi.backend = lib.mkDefault "iwd";

    # Require an explicit confirmation before permitting the removable fallback install.
    boot.loader = {
      efi.canTouchEfiVariables = false;
      grub = {
        device = "nodev";
        efiSupport = true;
      };
    };

    assertions = [
      {
        assertion = efi.efiSysMountPoint == "/boot" && (esp.fsType or null) == "vfat";
        message = "MacBook T2: mount the dedicated Linux FAT32 ESP at /boot.";
      }
      {
        assertion = grub.enable && grub.efiSupport && grub.efiInstallAsRemovable
          && !efi.canTouchEfiVariables && !grub.useOSProber;
        message = "MacBook T2: confirm Linux EFI fallback in the local module; keep NVRAM writes and OS prober disabled.";
      }
      {
        assertion = isPartition cfg.linuxEsp && isPartition cfg.macosEsp
          && lib.toLower cfg.linuxEsp != lib.toLower cfg.macosEsp
          && (esp.device or null) == cfg.linuxEsp;
        message = "MacBook T2: confirm distinct Linux and macOS ESP PARTUUID paths and match the Linux path in fileSystems./boot.";
      }
      {
        assertion = builtins.length grub.mirroredBoots == 1 && lib.all (entry:
          entry.path == "/boot" && (entry.efiSysMountPoint == null || entry.efiSysMountPoint == "/boot")
          && entry.devices == [ "nodev" ]
        ) grub.mirroredBoots;
        message = "MacBook T2: GRUB may write to the dedicated Linux ESP only.";
      }
      {
        assertion = !cfg.localFirmware.enable ||
          (builtins.pathExists (firmwareDir + "/brcm") && !config.hardware.apple-t2.firmware.enable);
        message = "MacBook T2: local firmware needs firmware/brcm and is exclusive with automatic extraction.";
      }
    ];

    # nixos-install enters /mnt as the target root and invokes the same boot action.
    system.preSwitchChecks.verifyLinuxEsp = ''
      case "$2" in
        boot|switch)
          findmnt=${pkgs.util-linux}/bin/findmnt
          readlink=${pkgs.coreutils}/bin/readlink
          lsblk=${pkgs.util-linux}/bin/lsblk
          esp_type=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
          linux=$("$readlink" -e ${lib.escapeShellArg (toString cfg.linuxEsp)}) || exit 1
          macos=$("$readlink" -e ${lib.escapeShellArg (toString cfg.macosEsp)}) || exit 1
          source=$("$findmnt" --noheadings --raw --mountpoint /boot --output SOURCE) || exit 1
          mounted=$("$readlink" -e "$source") || exit 1
          if [ ! -b "$linux" ] || [ ! -b "$macos" ] || [ "$linux" = "$macos" ] ||
             [ "$mounted" != "$linux" ] ||
             [ "$("$findmnt" --noheadings --raw --mountpoint /boot --output FSTYPE)" != vfat ] ||
             [ "$("$lsblk" -dn -o PARTTYPE "$linux")" != "$esp_type" ] ||
             [ "$("$lsblk" -dn -o PARTTYPE "$macos")" != "$esp_type" ] ||
             [ -e /boot/EFI/APPLE ]; then
            echo 'Refusing to update GRUB: /boot is not the confirmed Linux GPT ESP.' >&2
            exit 1
          fi
          ;;
      esac
    '';

    hardware.firmware = lib.mkIf cfg.localFirmware.enable [
      (pkgs.runCommand "macbook-t2-local-firmware" { src = firmwareDir + "/brcm"; } ''
        mkdir -p "$out/lib/firmware/brcm"
        cp -a "$src/." "$out/lib/firmware/brcm/"
      '')
    ];
    hardware.graphics.extraPackages = lib.mkIf cfg.intelMedia.enable [ pkgs.intel-media-driver ];
  };
}
