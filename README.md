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
git clone --branch installer https://github.com/MrKzya/NixOS-vladik.git
cd NixOS-vladik
sudo bash install.sh --dry-run
sudo bash install.sh
```

`--dry-run` показывает план без монтирования, записи на целевые разделы и изменений DNS. В обычном режиме установщик монтирует разделы, формирует аппаратный модуль, проверяет зависимости, устанавливает GRUB и настраивает пользователя. Собственная разметка и форматирование остаются за пределами установщика. [Установка](docs/INSTALLATION.md)

## Архитектура

`flake.nix` связывает аппаратные профили из `hosts/` с общими модулями из `modules/`. `home/` и `configs/` содержат Home Manager и оформление. `installer/` преобразует параметры интерфейса в локальный модуль Flake. Установленная конфигурация хранится в `/etc/nixos/NixOS-vladik`.

- [Конфигурация, пересборка и откат](docs/CONFIGURATION.md)
- [Переключатели компонентов](docs/COMPONENTS.md)
- [MacBook Air с Apple T2 и macOS](docs/MACBOOK-T2.md)
- [Готовое ядро и бинарный кеш](docs/BINARY-CACHE.md)
- [VMware и воспроизводимая проверка](docs/VMWARE.md)
- [Диагностика](docs/TROUBLESHOOTING.md)
- [История изменений](CHANGELOG.md)
