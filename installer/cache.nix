host:
let
  cfg = host.config;
  kernel = cfg.boot.kernelPackages.kernel;
  externalModules = map (pkg: pkg.outPath) cfg.boot.extraModulePackages;
in
{
  inherit (kernel) version;
  image = kernel.outPath;
  modules = (kernel.modules or kernel).outPath;
  inherit externalModules;
  initrdModules = cfg.boot.initrd.kernelModules;
}
