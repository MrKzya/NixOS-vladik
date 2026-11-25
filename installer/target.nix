# Imported only by an installation generated from this checkout.
{ configDir }:
{ lib, ... }:
let
  settings = builtins.fromJSON (builtins.readFile (configDir + "/settings.local.json"));
  inherit (settings) profile;
  mac = profile == "macbook";
  devices = settings.storage;
  byPartuuid = id: "/dev/disk/by-partuuid/" + id;
  switches = group: lib.mapAttrs (_: enabled: { enable = lib.mkOverride 90 enabled; })
    settings.components.${group};
in
{
  imports = [ (configDir + "/hardware.generated.local.nix") ];

  networking.hostName = lib.mkOverride 90 settings.hostname;
  networking.networkmanager.insertNameservers = settings.nameservers;
  time.timeZone = settings.timezone;
  i18n.defaultLocale = settings.locale;

  mySystem = {
    user = settings.user;
    apps = switches "apps";
    gaming = switches "gaming";
    system = switches "system";
    bluetooth = (switches "hardware").bluetooth;
    desktop = lib.mapAttrs (_: value: lib.mkOverride 90 value) settings.desktop;
    grub.theme = lib.mkOverride 90 settings.theme;
  } // lib.optionalAttrs mac {
    macbook = {
      linuxEsp = byPartuuid devices.efiPartuuid;
      macosEsp = byPartuuid devices.applePartuuid;
      localFirmware.enable = lib.mkOverride 90 (settings.firmware == "live");
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/" + devices.rootUuid;
      inherit (devices) fsType;
      options = if devices.fsType == "btrfs" then [ "compress=zstd:3" "noatime" "subvolid=5" ]
        else [ "defaults" ];
    };
    "/boot" = {
      device = byPartuuid devices.efiPartuuid;
      fsType = "vfat";
      options = [ "umask=0077" ];
    };
  };

  boot.loader = {
    efi = {
      canTouchEfiVariables = lib.mkOverride 90 false;
      efiSysMountPoint = "/boot";
    };
    grub = {
      device = lib.mkOverride 90 "nodev";
      efiSupport = true;
      efiInstallAsRemovable = true;
      useOSProber = false;
    };
  };
} // lib.optionalAttrs mac {
  hardware.apple-t2.firmware = lib.mkIf (settings.firmware != "none" && settings.firmware != "live") {
    enable = lib.mkOverride 90 true;
    version = lib.mkOverride 90 settings.firmware;
  };
}
