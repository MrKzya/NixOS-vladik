# NixOS-vladik

Перенос конфигурации Arch Linux на NixOS для ThinkPad, Intel MacBook с Apple T2 и гостя VMware Workstation. Один хост имеет одну установку, одного пользователя и три режима загрузки.

| Режим | Среда | Для чего |
| --- | --- | --- |
| Default | Ly → Niri + DankMaterialShell + Vicinae | Повседневные приложения и исходное оформление Kanagawa |
| Gaming | Ly → KDE Plasma 6 Wayland | Steam, Proton из Steam, GameMode и MangoHud |
| Minimal | TTY | Fish, Starship, Fastfetch, Git, Pwgen, сеть и базовые утилиты |

Gaming и Minimal — независимые NixOS Specialisations. Они подключают те же настройки хоста, загрузчика и учётной записи. GRUB показывает оба режима рядом с Default и хранит предыдущие поколения. Файлы из домашнего каталога доступны при любом режиме. Пакеты других режимов хранятся в Nix Store для следующей загрузки.

## Где редактировать

| Место | Содержимое |
| --- | --- |
| `flake.nix`, `flake.lock` | Список устройств, специализации и закреплённые версии источников |
| `hosts/<имя>/configuration.nix` | Имя компьютера, загрузчик, настройки устройства |
| `hosts/<имя>/hardware-configuration.nix` | Диски, файловые системы, initrd и прочие данные от `nixos-generate-config` |
| `hosts/<имя>/packages.nix` | Дополнительные системные и пользовательские программы конкретного устройства |
| `hosts/<имя>/niri/` | Мониторы и индивидуальный автозапуск |
| `profiles/` | Состав каждого режима |
| `modules/` | Базовая система, загрузчик, графический сеанс и T2 |
| `home/` | Home Manager, пользовательские программы и подключение dotfiles |
| `configs/` | KDL, JSON, Fish, Kitty CONF, Ly INI, палитры и плагин DMS |
| `pkgs/` | Пакеты Karing и TG WS Proxy из закреплённых upstream-архивов |
| `scripts/` | Проверки и создание начальных пользовательских файлов |
| `docs/` | Развёртывание из чистой NixOS в VMware Workstation |

Общие системные пакеты добавляйте в `modules/system/base.nix`, пользовательские CLI — в `home/common.nix`, приложения и инструменты разработки Default — в `home/packages.nix`. Игровые программы добавляйте в `profiles/gaming.nix`. Чтобы удалить программу из режима, уберите её из соответствующего списка или выключите её `programs.*.enable` / `services.*.enable`. Для пользовательского пакета только на одном хосте добавьте в его `packages.nix`, например:

```nix
{ config, lib, pkgs, ... }:
{
  home-manager.users.${config.mySystem.user}.home.packages =
    lib.mkIf config.programs.niri.enable [ pkgs.inxi ];
}
```

Параметры ниже можно задавать в `hosts/<имя>/configuration.nix`. Общие объявления опций подключаются через `common` в `flake.nix`. Если модуль нужен одному режиму, добавьте его в `imports` этого режима.

```nix
mySystem.cursor.size = 32;
mySystem.bluetooth.enable = true;
mySystem.grub.theme = "world-selection"; # minegrub | world-selection | none
nix.gc = {
  automatic = true;
  dates = "weekly";
  options = "--delete-older-than 30d";
};
```

В модуле `modules/system/workstation.nix` доступны `mySystem.development.enable`, `mySystem.networkApps.enable` и `mySystem.binaryCompatibility.enable`. Последний включает Nix-ld и регистрацию формата AppImage и по умолчанию выключен.

## Dotfiles и внешний вид

- Горячие клавиши редактируются в `configs/niri/cfg/keybinds.kdl`. Общие правила окон, анимации, палитра, раскладки и ввод находятся в соседних файлах. Штатные жесты поставляет Niri. Настройки мониторов берутся из `hosts/<имя>/niri/display.kdl`. Имя и доступные режимы покажет `niri msg outputs`. В KDL узел `output "<имя>"` может задавать `mode "ширинаxвысота@частота"` и `scale`. ThinkPad содержит отключённый пример из исходного проекта. По умолчанию оба хоста используют автоматически выбранные режимы.
- DMS, Vicinae и индексатор запускаются вместе с `niri.service`. Общие дополнительные программы сеанса добавляйте через модуль Niri. Программы одного устройства добавляйте в `hosts/<имя>/niri/autostart.kdl` через `spawn-at-startup`.
- Home Manager устанавливает файлы Niri, Kitty, Fish и палитру DMS как ссылки на Nix Store. Правьте их в репозитории. Если целевые файлы уже существуют после Arch, перед первым применением сохраните их отдельно, сверяясь с путями в `home/`. Home Manager остановит активацию при конфликте с локальным файлом.
- `configs/dms/settings.json`, `configs/dms/plugin_settings.json`, `configs/vicinae/settings.json`, `configs/fish/fish_variables` и фрагменты `configs/niri/dms/` служат начальными данными. При первом появлении профиля Home Manager создаёт только отсутствующие файлы. Копии доступны для записи и продолжают жить при переходе между режимами. Чтобы применить новое значение из шаблона в уже настроенном профиле, перенесите нужное поле или файл после резервного копирования. Для DMS 2.x путь — `$XDG_CONFIG_HOME/dms/`. При наличии старых данных в `DankMaterialShell/` первичный запуск DMS сам переносит их в новый каталог.
- Фрагменты `niri/dms/*.kdl` сохранены для DMS. Как и в исходной конфигурации, главный KDL их не включает. Поэтому разрешение и масштаб редактируются в файле хоста. Для обоев используйте настройку DMS и собственные изображения.
- В графических режимах установлен XCursor `macOS`, размер по умолчанию 24. Niri получает его из встроенного фрагмента KDL, GTK — из настроек интерфейса, XWayland и Qt — через тему и переменные сеанса, Plasma — из системного `kcminputrc`. Уже настроенный DMS хранит собственный размер в изменяемом JSON. После изменения параметра хоста на существующей установке выставьте такой же размер в DMS, а в Plasma проверьте, что пользовательский `kcminputrc` не переопределяет системное значение.

## Подготовка устройств

Аппаратные файлы физических устройств являются шаблонами. Подготовку выполняйте в Linux на целевом устройстве после определения и монтирования настоящих файловых систем. При корневой системе, смонтированной под `/mnt`, команда ниже выводит конфигурацию на экран:

```bash
nixos-generate-config --root /mnt --show-hardware-config
lsblk -f
findmnt --real
```

Перенесите вывод в файл нужного хоста, проверьте корень, ESP, swap, шифрование, доступные модули initrd и архитектуру. Проверьте, что `boot.loader.efi.efiSysMountPoint` совпадает с точкой монтирования ESP в установленной системе. По умолчанию это `/boot`. Проверьте модель устройства, наличие дискретной графики, разрешение и масштаб встроенного экрана, внешние дисплеи и файловые системы. Имена и разрешения можно записать после запуска Niri через `niri msg outputs`.

### ThinkPad

Предусмотрен GRUB в UEFI. Подтвердите режим загрузки через `test -d /sys/firmware/efi` из Linux и сверьте ESP. Для создания записи UEFI настройте `boot.loader.efi.canTouchEfiVariables` после проверки текущей схемы загрузки. Для Legacy BIOS придётся выключить `efiSupport` и указать подтверждённое устройство GRUB. Модель и тип графики в исходниках неизвестны. После определения модели можно подключить соответствующий модуль из `nixos-hardware` в `hosts/thinkpad/configuration.nix`. В графических профилях включён стандартный Power Profiles Daemon.

### Intel MacBook с Apple T2

Общий модуль подключает `nixos-hardware.nixosModules.apple-t2`. Закреплённая версия использует T2-ядро ветки `stable`, загружает `apple-bce` в initrd и добавляет конфигурацию звука и параметры suspend/IOMMU. Для Wi-Fi NetworkManager использует iwd. Старые имена initramfs-модулей из Arch не нужны для этого ядра. Проверьте ввод и накопитель на T2-совместимой live-системе. Если Wi-Fi или встроенная клавиатура в live-среде недоступны, подготовьте проводное подключение и внешнее USB-устройство ввода. [Инструкция t2linux](https://wiki.t2linux.org/distributions/nixos/installation/)

- Отдельно проверьте **выделенный FAT32 ESP для Linux**. После проверки пути и устройства установите `boot.loader.grub.efiInstallAsRemovable = true` в аппаратном файле MacBook. Запись NVRAM остаётся выключенной. Загрузку можно выбрать через меню Apple при старте с Option. Используйте проверенный ESP Linux с учётом соседней установки macOS.
- Wi-Fi и Bluetooth Broadcom требуют firmware. Вариант для NixOS — `hardware.apple-t2.firmware.enable = true` с `firmware.version` равным `"sonoma"`, `"ventura"` или `"monterey"` по модели. Модуль загружает и извлекает firmware из образа Apple. Если для вашей модели нужно извлечение из существующей macOS, воспользуйтесь официальной инструкцией и храните извлечённые файлы локально. [Модуль T2](https://github.com/NixOS/nixos-hardware/tree/ff49dbf39553717ac8e0f4d5085fa0ca10c1031f/apple/t2), [руководство по firmware](https://wiki.t2linux.org/guides/wifi-bluetooth/)
- При подтверждённой Touch Bar можно включить `hardware.apple.touchBar.enable`. При подтверждённой необходимости управления вентиляторами задайте `services.t2fanrd.enable` и конфигурацию для обнаруженных датчиков и вентиляторов. `hardware.apple-t2.enableIGPU` включается только для подходящей модели с AMD dGPU. [Модуль Touch Bar](https://github.com/NixOS/nixpkgs/blob/2786a2a72088ecf32aea5b3ec52099e6a7cff78f/nixos/modules/hardware/apple-touchbar.nix), [руководство по вентиляторам](https://wiki.t2linux.org/guides/fan/)

### VMware Workstation на Windows

Хост `vmware` рассчитан на чистую NixOS, установленную с официального x86-64 ISO в UEFI. Внутри гостя скопируйте аппаратный модуль в игнорируемый файл `hosts/vmware/hardware-configuration.local.nix`. При сборке укажите `path:$PWD#vmware`, чтобы Nix прочитал локальный файл. Настройки 3D, диагностика и откат описаны в [docs/VMWARE.md](docs/VMWARE.md).

### Новый компьютер или специализация

Для компьютера создайте `hosts/<имя>/`, добавьте его `configuration.nix`, реальную аппаратную конфигурацию и два файла Niri. Зарегистрируйте хост в `flake.nix` по образцу `thinkpad = mkHost ./hosts/thinkpad;`. Шаблон рассчитан на x86_64. Для другой архитектуры проверьте совместимость приложений, ядра, Steam и темы GRUB.

Для нового режима создайте модуль в `profiles/` и добавьте его в `specialisation` внутри `mkHost`. Используйте общую базу `common` и `inheritParentConfig = false`, если режиму нужны собственные службы и набор приложений. При необходимости добавьте импорт в конкретный файл хоста через условие по роли или наличию нужной службы.

## Сборка, профили и обслуживание

Команды рассчитаны на запуск из каталога `NixOS-vladik`. Форма `path:$PWD` работает и когда новая папка ещё не добавлена в индекс внешнего Git-репозитория. После заполнения аппаратных файлов соберите нужную конфигурацию, затем запланируйте её применение при перезагрузке уже установленной NixOS:

```bash
nixos-rebuild build --flake "path:$PWD#thinkpad"
sudo nixos-rebuild boot --flake "path:$PWD#thinkpad"
```

Для MacBook укажите `#macbook`. При первой настройке учётной записи задайте пароль на самом устройстве через `sudo passwd vladik` из административной сессии. После перезагрузки выберите режим в GRUB. Если поколение ведёт себя плохо, загрузите предыдущее через меню GRUB. Чтобы вернуть предыдущее поколение по умолчанию, запустите `sudo nixos-rebuild boot --rollback`. Для отката исходников восстановите проверенную ревизию вместе с её `flake.lock` и соберите её снова.

Для Windows на отдельном разделе можно вручную включить `boot.loader.grub.useOSProber = true` на нужном хосте после проверки дисков. GRUB автоматически раскладывает режимы по поколениям. Обе темы Minegrub подключены через upstream-модули, выбранная тема применяется ко всему меню.

```bash
nix flake update --flake "path:$PWD"
nix flake check --keep-going --all-systems --no-build "path:$PWD"
nix store gc
```

После обновления проверьте diff `flake.lock` и соберите конфигурацию. Обычный `nix store gc` освобождает недостижимые пути. Если требуется убрать старые поколения, это отдельное решение. При включении `nix.gc.automatic` настройте срок хранения, достаточный для отката. Версии состояния системы и Home Manager зафиксированы на 26.05 и меняются отдельно от обновления входов.

## Тестовая ВМ QEMU/KVM

На x86_64 Linux с Nix доступны отдельные проверки и QEMU-гость с UEFI и теми же режимами. Владелец подтвердил сборку и загрузку гостя на ThinkPad под Arch, работу Niri + DMS, Plasma, Ly, терминала и курсора. В этом запуске Niri использовал VirGL и nixGLIntel на стороне Arch.

```bash
nix build --no-link "path:$PWD#checks.x86_64-linux.profiles"
nix build --no-link "path:$PWD#checks.x86_64-linux.niri-vm"
nix build "path:$PWD#vm"
NIX_DISK_IMAGE="$PWD/vladik-vm.qcow2" ./result/bin/run-vladik-vm-vm
```

В QEMU-госте `#vm` используется тестовая учётная запись `vladik` / `vm-only`. Диск QEMU создаётся как обычный файл. Полный `flake check` требует аппаратных данных ThinkPad, MacBook и VMware. До их заполнения `--keep-going` позволяет вычислить QEMU-гостя и отдельные проверки, включая `checks.x86_64-linux.niri-vmware`.

## Публикация

Проект можно вынести в самостоятельный Git-репозиторий, сохранив исходники, `flake.lock` и лицензии. Результаты аудита и ограничения описаны в [SECURITY-AUDIT.md](SECURITY-AUDIT.md). Состояние миграции и оставшиеся проверки указаны в [MIGRATION.md](MIGRATION.md) и [TODO.md](TODO.md).
