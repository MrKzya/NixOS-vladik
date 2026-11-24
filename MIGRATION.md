# Отчёт о миграции

Проверены рабочие файлы исходного проекта, включая скрытую `.config`, содержимое `etc`, символическую ссылку Kitty, файлы документации и лицензии, `install.sh` и `macos-t2.sh`. Проект NixOS самодостаточен, его входы закреплены в `flake.lock`. Установочные скрипты Arch использованы как источник сведений о пакетах, сервисах и загрузчике.

## Карта компонентов

| Исходник | В NixOS | Перенос и проверка |
| --- | --- | --- |
| `.config/niri/config.kdl` и `cfg/` | `configs/niri/`, `hosts/*/niri/`, `home/niri.nix` | Модульная структура KDL сохранена. Все 92 активные клавиши сверены с исходником. Один биндинг изменил имя команды Zen. Правила Kitty и Steam, радиус 20, отступ 8, ширина колонок, ввод и анимации сохранены. KDL разобран для всех хостов после вычисления Home Manager. Проверены include и названия 46 действий по исходникам Niri 26.04. |
| `.config/niri/cfg/display.kdl` | `hosts/*/niri/display.kdl` | Единственный режим, `DP-1 2560x1440@359.979 scale 1`, был отключён. Сохранён как отключённый пример ThinkPad. Реальные выходы и масштаб определяются отдельно. |
| `.config/niri/cfg/autostart.kdl` | `modules/desktop/niri.nix`, `hosts/*/niri/autostart.kdl` | DMS и Vicinae привязаны к Niri через systemd. Добавлен сервис индексатора Dux Search в том же сеансе. Файлы хостов оставлены для индивидуальных запусков. |
| `.config/niri/dms/*.kdl` | `configs/niri/dms/` | Восемь начальных фрагментов на своих местах, включая пустые файлы. DMS получает изменяемые копии. Основной KDL сохраняет исходный набор применяемых правил без подключения этих фрагментов. |
| `.config/niri/noctalia.kdl` | `configs/niri/cfg/kanagawa.kdl` | Палитра focus-ring, border, shadow, tab-indicator, insert-hint и recent-windows перенесена побайтово. Изменилось имя файла и путь include. |
| `.config/DankMaterialShell/settings.json` и `themes/kanagawa/theme.json` | `configs/dms/`, `home/niri.nix` | Сохранён JSON панели, часов, погоды, буфера обмена, lock screen, Matugen и других настроек. На первом запуске используется актуальный каталог DMS 2.x, абсолютный XDG-путь темы и параметры курсора. JSON проверен. Отображение и миграции схемы нужно увидеть в Linux-сеансе. |
| `.config/DankMaterialShell/plugins/dankKbdLayout/` | `configs/dms/dankKbdLayout/` | QML, манифест и GPL сохранены без изменений. Плагин регистрируется upstream-модулем DMS и доступен для добавления в панель. Штатная расстановка виджетов в исходном `barConfigs` сохранена. Команды IPC виджета сверены с Niri 26.04. |
| `.config/kitty/` | `configs/kitty/`, `home/graphical.nix` | `kitty.conf` и активная `kanagawa.conf` без изменений. Явные шрифты, прозрачность 0.65, padding 5, курсор underline и trail, Fish и размеры окна сохранены. Историческая цель `current-theme.conf` сохранена как `themes/kanagawa-generated.conf`. Активный Kitty по-прежнему включает `kanagawa.conf`. |
| `.config/fish/` | `configs/fish/`, `home/common.nix` | Функция `fish_user_key_bindings`, Ctrl+L, `EDITOR=nano`, Starship и вывод Fastfetch сохранены. Снимок универсальных переменных Fish идёт как начальное состояние изменяемого файла. Синтаксис Fish проверен. Пользовательских алиасов и отдельных конфигураций Starship/Fastfetch в исходниках нет. |
| `.config/vicinae/settings.json` | `configs/vicinae/settings.json`, `modules/desktop/niri.nix` | Alt+Space продолжает вызывать `vicinae toggle`. JSONC доступен для изменения из GUI. Исходник указывал на тему `noctalia`, файла темы в проекте нет. Для чистого профиля выбран встроенный `kanagawa` из Vicinae 0.30.0. Существующий пользовательский файл сохраняется при активации. |
| `etc/ly/config.ini`, `ly@tty2.service` | `configs/ly/config.ini`, `modules/desktop/{shared,ly-settings}.nix` | Сохранились часы, отступы, формат цвета, клавиши и tty2. NixOS предоставляет PATH, команды яркости, выключения и перезагрузки, PAM, список сессий и setup. Пустой пароль отключён. Автовход остался выключен. NixOS регистрирует обе Wayland-сессии в соответствующих профилях. Сам вход через Ly требует проверки в ВМ. |
| Minegrub из `install.sh` | `modules/boot/grub.nix` | Обе темы берутся из закреплённых официальных Flakes. Основное меню Minegrub активно по умолчанию, World Selection можно выбрать как альтернативу. Upstream GRUB NixOS создаёт пункты Default, Gaming, Minimal и прежние поколения. OS Prober включается отдельно на нужном хосте. |
| `etc/pacman.conf`, `pacman`, `yay` | `flake.nix`, `flake.lock`, списки пакетов | Репозитории Arch, управление через AUR и его параметры загрузки заменены фиксированными входами Nix. Способ получения каждого приложения указан ниже. |
| `macos-t2.sh` | `hosts/macbook/`, `modules/hardware/apple-t2.nix` | `apple-bce`, стабильное T2-ядро, настройки звука и аргументы suspend/IOMMU предоставляет nixos-hardware. NetworkManager с iwd; Broadcom firmware, дополнительные вентиляторы и Touch Bar проверяются по модели. EFI fallback сохраняет первоначальное намерение отдельного ESP и отсутствия записи NVRAM. |
| Обои, шрифты, курсор | `home/graphical.nix`, `home/niri.nix`, `profiles/default.nix` | Файлов обоев в исходном проекте нет. JetBrains Mono Nerd Font сохранён; Inter и Fira Code явно включены по настройкам DMS. Добавлена XCursor-тема `macOS` из `apple-cursor`. Проверены `index.theme`, алиасы `pointer`, `pointing_hand` → `hand2` и само растровое изображение белой перчатки. Размер 24 по умолчанию. |

## Пакеты из install.sh

| Имена в Arch | В новом проекте |
| --- | --- |
| `niri kitty wayland polkit-gnome ttf-jetbrains-mono-nerd ly` | Модули Niri и Ly, Kitty, Wayland как зависимость композитора и клиентских пакетов, `polkit_gnome` доступен как пакет. В сеансе DMS работает его встроенный polkit-агент. `nerd-fonts.jetbrains-mono` задаётся через `fonts.packages`. |
| `base-devel` | Компилятор GCC, binutils, Make, Autoconf, Automake, pkg-config, patch, fakeroot, lex/yacc и вспомогательные инструменты в Default. Stdenv предоставляет инструменты для сборок Nix. |
| `fish starship git fastfetch nano tree` | Общая база всех профилей. Fish системная оболочка пользователя. Starship и Fastfetch подключены исходным Fish-конфигом. |
| `brightnessctl playerctl os-prober ntfs-3g dosfstools` | `brightnessctl` с rules пакета и `playerctl` в графических режимах, `os-prober` как утилита Default и опция GRUB, `ntfs3g` и `dosfstools` в общей базе. |
| `firefox obsidian telegram-desktop code` | `firefox`, `obsidian`, `telegram-desktop`, `vscode` из Nixpkgs. |
| `dms-shell-niri dms-shell dgop dsearch-bin` | `programs.dux-shell`, `dux-gop`, `programs.dux-search` из зафиксированного Nixpkgs. Системный пакет `dms` в Nixpkgs обозначает другой проект. У Dux Shell остаётся исполняемый файл `dms`. |
| `vicinae-bin nautilus` | `vicinae` и `nautilus` из Nixpkgs, пользовательская служба Vicinae запускает сервер в Niri. |
| `karing-bin tg-ws-proxy-bin` | Собственные Nix-выражения для x86_64 в `pkgs/`. Файлы .deb от разработчиков скачиваются по точным версиям и SHA-256. Проверены хэши, desktop-файлы и ELF-зависимости. Сборку и запуск нужно проверить на Linux. [Karing](https://github.com/KaringX/karing/releases/tag/v1.2.26.2934), [TG WS Proxy](https://github.com/Flowseal/tg-ws-proxy/releases/tag/v1.12.0) |
| `zen-browser` из Mod+B | Установлен Zen Beta от поддерживаемого стороннего Flake. Его исполняемый файл — `zen-beta`. [Zen Browser Flake](https://github.com/0xc000022070/zen-browser-flake) |

Пакеты Gaming добавлены по запросу. Plasma работает в стандартной Wayland-сессии, Proton устанавливается через клиент Steam. Графическая система и PipeWire с 32-битной поддержкой включаются только в нужных режимах. Настройки Steam, Karing и TG WS Proxy остаются в домашнем каталоге. Для Karing обработан обычный запуск приложения. Режим TUN upstream ожидает привилегированный помощник с изменяемыми правами, поэтому его настройка требует отдельной работы с учётом Nix Store. [Обсуждение TUN в Karing](https://github.com/KaringX/karing/issues/1844)

## Изменения в поведении и оформлении

- Mod+B запускает `zen-beta`. Все остальные действия из активных биндов Niri сохранены. Вызовы `dms ipc call` для launcher, lock, powermenu, audio, mic, mpris и brightness сверены с зарегистрированными методами. Зависимости команд `kitty`, `zen-beta`, `nautilus` и `vicinae` входят в Default. [Исходники Niri 26.04](https://github.com/niri-wm/niri/tree/v26.04), [исходники DMS 2.1.2](https://github.com/duxlabs-dev/dux-shell/tree/v2.1.2)
- DMS и Vicinae по-прежнему стартуют с Niri. Вместо параллельных запусков из KDL и отдельного глобального сервиса используется один путь через systemd. Настройки самого Niri разделены на общие, аппаратные и начальные фрагменты DMS.
- В Niri заменён только блок курсора Adwaita и перенесены пути include. GTK получает параметры курсора через dconf. Qt и XWayland используют тему и переменные сеанса. В Plasma системный курсор задаётся в `kcminputrc`. Уже сохранённые настройки DMS остаются редактируемыми. [Apple Cursor](https://github.com/ful1e5/apple_cursor/releases/tag/v2.0.1)
- Для Vicinae выбрана Kanagawa из поставки программы. Точные старые цвета можно вернуть, если сохранился файл темы из домашнего каталога. Исторические палитры Niri и Kitty сохранили исходные значения. Noctalia Shell и её запуск отсутствуют в графе Flake, пакетах и службах. [Vicinae: каталог тем](https://docs.vicinae.com/theming/cli-tools)
- Команды Ly с Arch-путями обработаны модулем NixOS. Рестарт и выключение выполняет systemd. Команда запуска сессии и каталог Wayland-сессий формируются дисплейным менеджером. Экранный вход на tty2 сохраняется. [Модуль Ly](https://github.com/NixOS/nixpkgs/blob/2786a2a72088ecf32aea5b3ec52099e6a7cff78f/nixos/modules/services/display-managers/ly.nix), [модуль Plasma 6](https://github.com/NixOS/nixpkgs/blob/2786a2a72088ecf32aea5b3ec52099e6a7cff78f/nixos/modules/services/desktop-managers/plasma6.nix)
- Minegrub использует обычное меню GRUB с пунктами NixOS. Сохранена сама тема, а пункты выбора профилей и отката созданы NixOS. У World Selection отдельная настройка темы для всего меню. [Minegrub](https://github.com/Lxtharia/minegrub-theme), [Minegrub World Selection](https://github.com/Lxtharia/minegrub-world-sel-theme)

## Проверки первоначального переноса

На Apple Silicon macOS использовался официальный Nix 2.36.0 из временного каталога с отдельным локальным хранилищем. Получен настоящий `flake.lock`. Nix вычислил `toplevel` ВМ, вывод `vm` и все пять `checks.x86_64-linux`. Для всех девяти комбинаций устройства и режима вычислены пакеты системы, генерация Home Manager и ядро, включая `linux-t2 6.18.64` для MacBook. Проверка профилей вычислила пакеты, состав Home Manager, графические службы, общую учётную запись, общий каталог и общий набор файловых систем на всех хостах.

`nix flake check --all-systems --no-build --keep-going` вычислил ВМ, форматтер и проверки. Проверка полных конфигураций ThinkPad и MacBook ожидаемо остановилась на отсутствующих корневой файловой системе и EFI. Синтаксис KDL 1 проверен парсером `kdl-py` для 22 файлов. Дополнительно проверены синтаксис Fish и Bash, целевые файлы, список запускаемых из биндов команд и отсутствие секретов в перенесённых файлах.

Проверки `niri validate` имеют готовые Nix-выводы для трёх хостов. Были запущены сборки проверки Niri и ВМ. Временное хранилище Nix на macOS поддерживает вычисление, а при сборке вернуло `building using a diverted store is not supported on this platform`. Для `niri validate`, сборки, загрузки QEMU и проверки входа через Ly нужен x86_64 Linux-сборщик. Перечень аппаратных и сеансовых проверок находится в [TODO.md](TODO.md).

## VMware Workstation и подтверждённый тест QEMU

Владелец собрал и загрузил QEMU-гостя на ThinkPad под Arch Linux. Он подтвердил работу Niri и DMS, Plasma в Gaming, Ly, Fish, Kitty, Starship и оформления, включая курсор. В этом запуске Niri потребовались VirGL и nixGLIntel на стороне Arch. Тест охватывал QEMU/KVM. VMware и нативная установка на ThinkPad остаются отдельными сценариями.

Хост `vmware` подключён через общий `mkHost`. `vmware.service` включена во всех трёх профилях с условием `ConditionVirtualization=vmware`. `open-vm-tools-headless` предоставляет `vmtoolsd` без X11-помощника, vmblock и Xorg-драйвера мыши. Графические профили используют Mesa с SVGA, а драйвер ядра `vmwgfx` привязывается к виртуальной видеокарте. Бинды Niri, палитры, шрифты, курсор и `flake.lock` сохранены. [Модуль VMware в закреплённом Nixpkgs](https://github.com/NixOS/nixpkgs/blob/2786a2a72088ecf32aea5b3ec52099e6a7cff78f/nixos/modules/virtualisation/vmware-guest.nix), [Mesa SVGA3D](https://docs.mesa3d.org/drivers/svga3d.html)

Сценарий начинается с обычной установки с официального ISO. Данные дисков, EFI и initrd читаются из локальной копии аппаратного модуля. Инструкция находится в [docs/VMWARE.md](docs/VMWARE.md), проверка перед публикацией — в [SECURITY-AUDIT.md](SECURITY-AUDIT.md).

На этом этапе Nix вычислил системные пакеты и генерации Home Manager для всех трёх режимов VMware. Из самостоятельного снимка проекта вычислены конфигурация QEMU и все шесть выходов `checks`. `flake check --no-build --keep-going` остановил полную проверку ThinkPad, MacBook и VMware на отсутствующих данных корня и EFI. Драйвер, изменение разрешения и графический вход в VMware предстоит проверить в госте.

### Результат чистой установки VMware

Владелец установил NixOS 26.05 с официального ISO в VMware Workstation и применил конфигурацию из GitHub. В госте подтверждена работа Niri, DMS, Ly, Kitty, Fish и оформления.

Vicinae находил приложения, но при запуске Firefox, VS Code и других программ получал `execve: No such file or directory`. Импорт `PATH` в пользовательский менеджер systemd не помог. Сработала явная переменная `PATH` в самой службе. Теперь `modules/desktop/niri.nix` задаёт проверенный порядок каталогов с `%u`, который systemd заменяет именем пользователя. В `PATH` службы добавлен `pactl` из пакета `pulseaudio`. Он работает с уже включённым PipeWire Pulse. [Звуковой бэкенд Vicinae](https://github.com/vicinaehq/vicinae/blob/v0.30.0/src/server/src/services/audio-control/pactl/pactl-audio-control.cpp)

Добавлен фон `Oboi.jpg`. В Default Home Manager задаёт проектный фон через IPC работающего DMS либо через поле `wallpaperPath` в изменяемом `session.json` до запуска DMS. Пользовательские обои и остальные поля сессии сохраняются. Для Gaming установлен пакет фонового изображения `Next`, который Breeze ищет по умолчанию. [IPC DMS](https://duxlabs.dev/docs/dankmaterialshell/keybinds-ipc/), [выбор фонового пакета в Plasma 6.8.3](https://invent.kde.org/plasma/plasma-workspace/-/blob/v6.8.3/wallpapers/defaultwallpaper.cpp)
