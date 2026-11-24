{ lib }:

let
  lines = lib.splitString "\n" (builtins.readFile ../../configs/ly/config.ini);
in
builtins.listToAttrs (lib.concatMap (line:
  let
    setting = builtins.match "([a-z0-9_]+) = (.*)" line;
  in
  lib.optional (setting != null) {
    name = builtins.elemAt setting 0;
    value = builtins.elemAt setting 1;
  }
) lines)
