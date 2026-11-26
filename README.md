# NixOS-vladik

Декларативная конфигурация NixOS и терминальный установщик для x86_64 UEFI. Основной сеанс — Niri, DankMaterialShell, Vicinae и Ly. Пользовательская конфигурация управляется Home Manager. KDE Plasma, Zen и игровые приложения подключаются отдельными флагами.

## Платформы

| Профиль | Платформа |
| --- | --- |
| `thinkpad` | Lenovo ThinkPad |
| `macbook` | Intel MacBook с Apple T2 и отдельным Linux ESP |
| `vmware` | VMware Workstation |
| `vm` | QEMU/KVM |

## Быстрая установка

Требуются NixOS Minimal Live ISO, сеть, подготовленный GPT-раздел Btrfs и отдельный пустой ESP FAT32. Минимум свободного места — 15 ГиБ на корне и 256 МиБ на ESP. MacBook требует [T2 Live ISO](docs/MACBOOK-T2.md).

```bash
git clone --single-branch --branch installer https://github.com/MrKzya/NixOS-vladik.git
cd NixOS-vladik
sudo bash install.sh --dry-run
sudo bash install.sh
```

В обоих режимах требуется UEFI. `--dry-run` показывает план без монтирования, записи на целевые разделы и изменений DNS. В обычном режиме проверьте план и введите `INSTALL`. Установщик автоматически сохраняет параметры, показывает операции Nix и позволяет повторить этап. Для переноса плана между сеансами используйте `--export-plan FILE` и `--plan FILE`. Разметку и форматирование выполняет пользователь. [Установка](docs/INSTALLATION.md)

## Архитектура

`flake.nix` связывает аппаратные профили из `hosts/` с общими модулями из `modules/`. `home/` и `configs/` содержат Home Manager и оформление. `installer/` преобразует параметры интерфейса в локальный модуль Flake. Установленная конфигурация хранится в `/etc/nixos/NixOS-vladik`.

- [Конфигурация, пересборка и откат](docs/CONFIGURATION.md)
- [Переключатели компонентов](docs/COMPONENTS.md)
- [MacBook Air с Apple T2 и macOS](docs/MACBOOK-T2.md)
- [Обновление работающей V2 на MacBook без Live ISO](docs/MACBOOK-UPGRADE.md)
- [Готовое ядро и бинарный кеш](docs/BINARY-CACHE.md)
- [VMware и воспроизводимая проверка](docs/VMWARE.md)
- [Диагностика](docs/TROUBLESHOOTING.md)
- [История изменений](CHANGELOG.md)
