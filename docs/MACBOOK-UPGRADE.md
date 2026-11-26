# Обновление MacBook Air с V2 до V3.1

Команды рассчитаны на работающую NixOS V2 на `MacBookAir9,1` с ядром 6.18.55 и отдельным Linux ESP в `/boot`. Вся работа выполняется из установленной системы. Корень, домашний каталог, существующий пароль, APFS и macOS сохраняются. Во время обновления в новый загрузчик записывается только Linux ESP. NVRAM и Apple ESP остаются вне этой операции.

V2 загружает `t2bce`. V3.1 использует подписанное ядро 6.18.35 и штатный для него `apple-bce`. Ввод и внутренний диск с этим ядром работали в T2 Live. Wi-Fi BCM4377, Bluetooth и suspend установленной V3.1 требуют проверки на MacBook. Автоматический suspend следует оставить выключенным до проверки. [Кеш и дерево модулей](BINARY-CACHE.md) · [Проверки оборудования](MACBOOK-T2.md)

## 1. Подготовить отдельный checkout

Откройте `bash` и выполняйте блоки в одной оболочке. В `old` укажите абсолютный путь к вашей рабочей копии V2, из которой раньше запускали `nixos-rebuild`. Если `/etc/nixos/NixOS-vladik` отсутствует или содержит другую копию, измените значение перед запуском.

```bash
set -euo pipefail
old=/etc/nixos/NixOS-vladik
new=$HOME/NixOS-vladik-v3.1
test -f "$old/flake.nix"
case "$(uname -r)" in 6.18.55*) ;; *) echo 'Expected the working 6.18.55 kernel.' >&2; exit 1 ;; esac
test "$(cat /sys/class/dmi/id/product_name)" = MacBookAir9,1
test ! -e "$new"
git clone --single-branch --branch installer https://github.com/MrKzya/NixOS-vladik.git "$new"

old_cfg="path:$old#nixosConfigurations.macbook.config"
old_option() { nix eval --no-update-lock-file "$old_cfg.$1" "${@:2}"; }
linux_esp=$(old_option mySystem.macbook.linuxEsp --raw)
apple_esp=$(old_option mySystem.macbook.macosEsp --raw)
old_user=$(old_option mySystem.user --raw)
test "$old_user" = "$(id -un)"
findmnt --mountpoint /boot --output SOURCE,FSTYPE,FSROOT
lsblk --output NAME,FSTYPE,UUID,PARTTYPE,PARTUUID,MOUNTPOINTS
sudo bash "$new/scripts/verify-linux-esp.sh" "$linux_esp" "$apple_esp"
```

Сверьте вывод с разделами V2. При ошибке проверки остановитесь и восстановите штатное монтирование именно Linux ESP в `/boot`. Apple ESP должен быть отдельным GPT-разделом.

## 2. Перенести локальные настройки

V3.1 по-прежнему умеет загружать прежний аппаратный модуль из `hardware-configuration.local.nix`. Для обновления существующей системы используйте этот совместимый путь. Файлы `installer.local.nix`, `hardware.generated.local.nix` и `settings.local.json` предназначены для установки на пустой корень и здесь не нужны.

```bash
local_dir=$new/hosts/macbook
old_hw=$old/hosts/macbook/hardware-configuration.local.nix
if [[ ! -f $old_hw ]]; then old_hw=$old/hosts/macbook/hardware-configuration.nix; fi
test -f "$old_hw"
install -m 0600 "$old_hw" "$local_dir/hardware.v2.local.nix"
if [[ -d $old/hosts/macbook/firmware/brcm ]]; then
  install -d -m 0700 "$local_dir/firmware"
  cp -a "$old/hosts/macbook/firmware/brcm" "$local_dir/firmware/"
fi
git -C "$new" check-ignore hosts/macbook/hardware.v2.local.nix hosts/macbook/firmware/brcm
grep -nE 'imports|fileSystems|t2bce|boot\.kernel|firmware|linuxEsp|macosEsp' "$local_dir/hardware.v2.local.nix" || true
```

Просмотрите копию через `nano "$local_dir/hardware.v2.local.nix"`. Сохраните `fileSystems`, параметры томов, swap и аппаратные настройки. Если исходный файл только подключал другой локальный модуль, перенесите и этот модуль по соответствующему относительному пути. Удалите из **копии** переопределения ядра 6.18.55, модуля `t2bce`, его параметров и добавляемых для него патчей. `apple-bce` назначает закреплённый модуль V3.1. Перенесите вручную нужные параметры из других локальных модулей V2, например настройки сети и компонентов, сохранив оригиналы в рабочей копии V2.

Следующий блок переносит вычисленные настройки учётной записи, EFI и Broadcom. Он приостанавливает автоматический GC в новой конфигурации до окончания проверки.

```bash
local_firmware=$(old_option mySystem.macbook.localFirmware.enable --json)
recovery_firmware=$(old_option hardware.apple-t2.firmware.enable --json)
firmware_version=$(old_option hardware.apple-t2.firmware.version --raw)
[[ $old_user =~ ^[a-z_][a-z0-9_-]*$ ]]
[[ $linux_esp =~ ^/dev/disk/by-partuuid/[a-fA-F0-9-]{36}$ ]]
[[ $apple_esp =~ ^/dev/disk/by-partuuid/[a-fA-F0-9-]{36}$ ]]
[[ $firmware_version =~ ^[a-z]+$ ]]
if [[ $local_firmware == true ]]; then test -d "$local_dir/firmware/brcm"; fi
umask 077
cat > "$local_dir/hardware-configuration.local.nix" <<EOF
{ lib, ... }: {
  imports = [ ./hardware.v2.local.nix ];
  mySystem.user = lib.mkForce "$old_user";
  mySystem.macbook.linuxEsp = lib.mkForce "$linux_esp";
  mySystem.macbook.macosEsp = lib.mkForce "$apple_esp";
  mySystem.macbook.localFirmware.enable = lib.mkForce $local_firmware;
  hardware.apple-t2.firmware.enable = lib.mkForce $recovery_firmware;
  hardware.apple-t2.firmware.version = lib.mkForce "$firmware_version";
  boot.loader.grub.efiInstallAsRemovable = lib.mkForce true;
  nix.gc.automatic = false;
}
EOF
new_cfg="path:$new#nixosConfigurations.macbook.config"
diff -u <(old_option fileSystems --json) <(nix eval --json --no-update-lock-file "$new_cfg.fileSystems")
test "$(old_option "users.users.$old_user.home" --raw)" = \
  "$(nix eval --raw --no-update-lock-file "$new_cfg.users.users.$old_user.home")"
nix eval --raw --no-update-lock-file "$new_cfg.system.build.toplevel.drvPath"
```

Если сравнение файловых систем показало расхождение, проверьте каждый путь и параметр по работающей V2. Продолжайте после восстановления прежнего корня и `/boot`. Этот шаг также выполняет проверки NixOS для отдельного Linux ESP, выключенного OS Prober и запрета записи NVRAM.

## 3. Сохранить рабочее поколение и выполнить сборку

```bash
sudo systemctl stop nix-gc.timer
if systemctl is-active --quiet nix-gc.service; then
  echo 'GC is already running. Wait for it to finish before proceeding.' >&2
  exit 1
fi
rollback=/nix/var/nix/profiles/system-profiles/known_good_6_18_55
sudo install -d /nix/var/nix/profiles/system-profiles
sudo nix-env --profile "$rollback" --set "$(readlink -f /run/current-system)"
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations

cache_url=$(nix eval --raw --file "$new/modules/hardware/t2-cache.nix" url)
cache_key=$(nix eval --raw --file "$new/modules/hardware/t2-cache.nix" key)
paths=$(nix eval --raw --no-update-lock-file "path:$new#nixosConfigurations.macbook" \
  --apply "host: let r = ($(cat "$new/installer/cache.nix")) host; in
    assert r.version == \"6.18.35\" && builtins.elem \"apple-bce\" r.initrdModules
      && !(builtins.elem \"t2bce\" r.initrdModules);
    builtins.concatStringsSep \"\n\" ([r.image r.modules] ++ r.externalModules)")
kernel_roots=$(sudo mktemp -d /var/tmp/nixos-vladik-t2.XXXXXXXX)
while IFS= read -r object; do
  sudo nix-store --realise "$object" --indirect --add-root "$kernel_roots/${object##*/}" \
    --option max-jobs 0 --option builders '' --option fallback false \
    --option require-sigs true --option extra-substituters "$cache_url" \
    --option extra-trusted-public-keys "$cache_key"
done <<< "$paths"

build_dir=$(mktemp -d)
cd "$build_dir"
sudo nixos-rebuild build --no-update-lock-file --flake "path:$new#macbook"
readlink -f result/kernel
```

Если точный объект отсутствует в подписанном кеше, команда останавливается до пересборки. При успешной сборке проверьте, что `result/kernel` указывает на 6.18.35. Текущая система по-прежнему загружена с 6.18.55.

## 4. Подготовить загрузку и откат

```bash
sudo bash "$new/scripts/verify-linux-esp.sh" "$linux_esp" "$apple_esp"
sudo nixos-rebuild boot --no-update-lock-file --flake "path:$new#macbook"
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
```

Перезагрузитесь и при необходимости выберите **EFI Boot** через Option. Проверьте `uname -r`, `lsmod | grep apple_bce`, монтирование `/boot`, вход прежним пользователем, Niri, клавиатуру, Wi‑Fi и Bluetooth. Проверьте самостоятельную загрузку macOS через Option.

При проблемах выберите поколение с ядром 6.18.55 в **NixOS - All configurations** или закреплённый профиль **NixOS - Profile 'known_good_6_18_55'**. Если рабочее поколение нужно вернуть и в первый пункт, после загрузки с 6.18.55 выполните следующие команды. Они проверяют Linux ESP и назначают рабочую конфигурацию для последующей загрузки.

```bash
case "$(uname -r)" in 6.18.55*) ;; *) exit 1 ;; esac
sudo bash "$new/scripts/verify-linux-esp.sh" "$linux_esp" "$apple_esp"
known_good=$(readlink -f /run/current-system)
sudo nix-env --profile /nix/var/nix/profiles/system --set "$known_good"
sudo "$known_good/bin/switch-to-configuration" boot
```

После перезагрузки переменные оболочки нужно заново задать из первого блока. До завершения тестирования не запускайте GC и не удаляйте закреплённый профиль. Исходную рабочую копию V2 и пользовательские данные на всём протяжении обновления можно продолжать использовать.
