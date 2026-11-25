host:
let
  inherit (host) config;
  inherit (config.mySystem) apps desktop gaming grub system bluetooth;
in
{
  hostname = config.networking.hostName;
  user = config.mySystem.user;
  timezone = config.time.timeZone;
  locale = config.i18n.defaultLocale;
  inherit desktop;
  theme = grub.theme;
  components = builtins.mapAttrs (_: builtins.mapAttrs (_: option: option.enable)) {
    inherit apps gaming system;
    hardware = { inherit bluetooth; };
  };
}
