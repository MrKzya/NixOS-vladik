# Компоненты NixOS-vladik

Общие значения заданы в `hosts/<профиль>/configuration.nix`. Установка V3 записывает выбор в `settings.local.json`. Изменение одного профиля не влияет на остальные.

## Графика

| Опция в `mySystem.desktop` | По умолчанию | Действие |
| --- | --- | --- |
| `niri.enable` | true | Wayland-сеанс Niri, XWayland через Satellite, KDL, GNOME/GTK-порталы |
| `plasma.enable` | false | Plasma 6 Wayland, собственный портал и фон Breeze |
| `dms.enable` | true | DMS, плагин раскладки, Dux Search и фон проекта в сеансе Niri |
| `vicinae.enable` | true | Vicinae в Niri, Node.js для расширений, рабочий PATH и pactl |
| `defaultSession` | null | NixOS выбирает Niri при его наличии, иначе Plasma. Явно можно выбрать `"niri"` или `"plasma"`, если она включена. Ly сохраняет последний выбор сеанса |

DMS и Vicinae подключаются только при включённом Niri. Niri с DMS использует встроенный агент polkit, без DMS используется агент GNOME, привязанный к Niri. Plasma запускает свой агент. При наличии графического сеанса включаются Ly, PipeWire Pulse, ускорение Mesa и общий курсор. При обоих выключенных окружениях система стартует в TTY. Bluetooth и пользовательские приложения управляются независимо от способа входа.

## Приложения

| Опция `mySystem.apps.<имя>.enable` | По умолчанию | Пакет или зависимость |
| --- | --- | --- |
| `firefox` | true | `firefox`, запускается по Mod+B, если Zen выключен |
| `zen` | false | `zen-beta` из уже закреплённого Flake, получает приоритет на Mod+B |
| `telegram` | true | `telegram-desktop` |
| `vesktop` | false | `vesktop` |
| `obsidian` | true | `obsidian` |
| `vscode` | true | `vscode`, устанавливается независимо от инструментария разработки |
| `zed` | false | `zed-editor` |
| `kitty` | true | `kitty`, конфигурация и Mod+Return |
| `nautilus` | true | `nautilus`, GVfs в графическом сеансе, Mod+E. При отключении Niri использует GTK-портал для выбора файлов |
| `obs` | false | `obs-studio`, захват Wayland через существующие PipeWire и портал композитора |
| `mpv` | false | `mpv` |
| `vlc` | false | `vlc` |
| `karing` | true | `pkgs/karing.nix`; TUN с привилегиями остаётся отдельной настройкой |
| `tgProxy` | true | `pkgs/tg-ws-proxy.nix` |
| `gpuScreenRecorder` | false | Штатный модуль NixOS, UI, recorder и необходимые wrappers. Возможность захвата зависит от GPU |
| `starship`, `fastfetch`, `pwgen`, `tmux`, `playerctl` | true | Одноимённые пакеты. Fish запускает Starship и Fastfetch при их наличии |

При отключении приложения его биндинг становится неактивен. Это касается Mod+B без обоих браузеров, Mod+Return без Kitty, Mod+E без Nautilus и Alt+Space без Vicinae. DMS-запуск, экран блокировки и меню сессии доступны с DMS. Без DMS медиаклавиши используют `wpctl`, `brightnessctl` и включённый `playerctl`; отключённый Playerctl убирает команды управления воспроизведением в этом варианте. Прочие привязки остаются из исходного KDL.

## Игры и система

Все `mySystem.gaming.<имя>.enable` выключены по умолчанию.

| Имя | Действие |
| --- | --- |
| `steam` | `programs.steam`, 32-битная графика и ALSA при включённом PipeWire |
| `heroic`, `lutris` | `heroic`, `lutris`; для запуска Wine активируется 32-битная графика и, при включённом PipeWire, ALSA |
| `protonupQt`, `prismLauncher` | `protonup-qt`, `prismlauncher` |
| `gamemode`, `mangohud` | `programs.gamemode`, пакет `mangohud` |

PortProton устанавливается из Flathub после включения `mySystem.system.flatpak.enable` и пересборки.

```bash
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub ru.linux_gaming.PortProton
```

Flatpak-приложение, его Wine Runtime и обновления управляются отдельно от Flake. [PortProton на Flathub](https://flathub.org/apps/ru.linux_gaming.PortProton)

| Опция `mySystem.system.<имя>.enable` | По умолчанию | Действие |
| --- | --- | --- |
| `development` | true | GCC, Make, binutils, pkg-config, autoconf, automake, patch и инструменты сборки |
| `osProber` | true | Утилита `os-prober` для ручного использования. Вызов из GRUB задаётся отдельно через `boot.loader.grub.useOSProber`, по умолчанию false |
| `flatpak` | false | Flatpak и XDG Portals |
| `appimage` | false | Поддержка AppImage и binfmt |
| `nixLd` | false | Nix-ld для совместимых сторонних бинарников |

Fish, NetworkManager, Git, Nano и основные дисковые/сетевые утилиты входят в базу. `mySystem.user` по умолчанию `"vladik"`. `mySystem.bluetooth.enable` включён на физических хостах, выключен в гостях. `mySystem.cursor.size` равен 24. `mySystem.grub.theme` принимает `"minegrub"`, `"world-selection"` или `"none"`. Специальные опции T2 перечислены в [MACBOOK-T2.md](MACBOOK-T2.md), параметры GC — в [CONFIGURATION.md](CONFIGURATION.md#nix-store).

## Примеры

Для двух графических сеансов достаточно `desktop.plasma.enable = true` при включённом Niri. Steam подключается через `gaming.steam.enable = true`. Для TTY оба графических флага выключены, а `desktop.defaultSession = null`. Опциональные приложения можно выключать независимо. В `settings.local.json` эти значения представлены полями `desktop.<среда>.enable` и `components.<группа>.<имя>`.
