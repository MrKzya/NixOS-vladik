# Конфигурация

| Путь | Назначение |
| --- | --- |
| `hosts/<профиль>/configuration.nix` | Общие переключатели и настройки устройства |
| `hosts/<профиль>/settings.local.json` | Параметры, выбранные в установщике. Имеют приоритет над исходными значениями хоста |
| `hosts/<профиль>/hardware.generated.local.nix` | Сгенерированные аппаратные параметры |
| `hosts/<профиль>/installer.local.nix` | Подключение локальных файлов к Flake |
| `hosts/<профиль>/niri/` | Дисплеи, масштаб, пользовательский автозапуск |
| `modules/`, `home/`, `configs/` | Системные зависимости, Home Manager, оформление |

В установленной системе `<профиль>` — имя выхода Flake из плана установки, независимо от имени компьютера. Для рабочей установки V2 поддерживается прежний `hardware-configuration.local.nix`. `path:` включает игнорируемые локальные модули. [Локальные данные](../SECURITY-AUDIT.md)

```bash
cd /etc/nixos/NixOS-vladik
sudo git pull --ff-only
sudo nixos-rebuild build --flake "path:$PWD#vmware"
sudo nixos-rebuild boot --flake "path:$PWD#vmware"
```

`boot` применяет поколение при следующей загрузке, `switch` также применяет его в текущем сеансе. Сохранённые поколения доступны в GRUB. Отдельно остаётся тестовый выход `nix build .#vm` из чистого клона. Тестовый образ сохраняет стандартный диск QEMU NixOS с Ext4 и использует тестовую учётную запись `vladik` / `vm-only`. При установке профиля `vm` на виртуальный диск эти настройки гостевого образа отключаются.

## Nix Store

По умолчанию включены еженедельный GC, политика `--delete-older-than 14d` и `auto-optimise-store`. Старые поколения и прочие GC roots удерживают их зависимости. Поколения NixOS управляют откатом системы независимо от Btrfs. Удаление поколений с последующим GC уменьшает число доступных откатов. Игры Steam, Flatpak и личные кеши содержатся отдельно.

```bash
nix path-info --closure-size --human-readable /run/current-system
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
sudo nix store gc
```

## Обои

Исходное изображение — `assets/wallpapers/Oboi.jpg`. Замена JPEG в репозитории и пересборка обновляют проектный фон DMS и фон Breeze по умолчанию. Ручные настройки DMS сохраняются. Горячие клавиши Niri находятся в `configs/niri/cfg/keybinds.kdl`.
