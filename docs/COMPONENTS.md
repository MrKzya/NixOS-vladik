# Компоненты NixOS-vladik

Открой `hosts/<хост>/configuration.nix`. В каждом из четырёх файлов перечислен весь общий набор. Значения ниже совпадают с исходной конфигурацией V2 для всех хостов, кроме отмеченных аппаратных опций. Флаги независимы от состава других хостов.

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

Все `mySystem.gaming.<имя>.enable` выключены по умолчанию:

| Имя | Действие |
| --- | --- |
| `steam` | `programs.steam`, 32-битная графика и ALSA при включённом PipeWire |
| `heroic`, `lutris` | `heroic`, `lutris`; для запуска Wine активируется 32-битная графика и, при включённом PipeWire, ALSA |
| `protonupQt`, `prismLauncher` | `protonup-qt`, `prismlauncher` |
| `gamemode`, `mangohud` | `programs.gamemode`, пакет `mangohud` |

PortProton отсутствует в закреплённом Nixpkgs. Для ручной установки включи `mySystem.system.flatpak.enable`, пересобери хост и выполни:

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

Fish, NetworkManager, Git, Nano и основные дисковые/сетевые утилиты входят в базу. `mySystem.user` по умолчанию `"vladik"`. `mySystem.bluetooth.enable` включён на физических хостах, выключен в гостях. `mySystem.cursor.size` равен 24. `mySystem.grub.theme` принимает `"minegrub"`, `"world-selection"` или `"none"`. Специальные опции T2 перечислены в [MACBOOK-T2.md](MACBOOK-T2.md), параметры GC — в [README.md](../README.md#nix-store-и-откат).

## Примеры

В существующем блоке выбранного хоста для двух графических сеансов поменяй `desktop.plasma.enable = true;`. Для Steam в Niri поменяй `gaming.steam.enable = true;`. Plasma и Steam можно включать независимо. Для TTY установи `desktop.niri.enable` и `desktop.plasma.enable` в `false`, оставь `desktop.defaultSession = null`. Для компактной TTY-конфигурации также выключи ненужные графические приложения и игровые пакеты. При переходе с V1 прежние `development`, `binaryCompatibility` и `networkApps` из локальных настроек замени соответствующими новыми флагами.
