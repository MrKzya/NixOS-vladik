# NixOS-vladik в VMware Workstation на Windows

Для новой ВМ сначала установите чистую NixOS с официального ISO. Затем подключите аппаратную конфигурацию гостя и примените `#vmware`. Для уже установленной NixOS-vladik используйте [переход на V2](#переход-рабочей-vmware-на-v2). Инструкция рассчитана на Windows x86-64 и VMware Workstation.

## 1. Создайте виртуальную машину

1. На странице NixOS скачайте официальный **Graphical ISO, 64-bit Intel/AMD**. Для чистой установки подходит стабильный образ NixOS 26.05, соответствующий `system.stateVersion` проекта. GNOME или KDE можно выбрать в загрузочном меню ISO для live-среды. Рабочий стол установленной системы выбирается отдельно в установщике. [Скачать NixOS](https://nixos.org/download/)
2. В Workstation выберите **File → New Virtual Machine**. Создайте одну машину типа Linux x86-64. Если отдельного пункта NixOS нет, выберите **Other Linux 64-bit**. При предложении Easy Install создайте машину с вариантом **I will install the operating system later**, затем подключите скачанный ISO через **CD/DVD → Use ISO image file**.
3. Выделите **4 vCPU, 8 ГиБ RAM и 80 ГиБ** на новом расширяемом виртуальном диске. Если планируете устанавливать игры, увеличьте диск с учётом их размера. Для первого теста достаточно NAT.
4. В настройках выключенной ВМ выберите **UEFI**. Обычно это **VM → Settings → Options → Advanced → Firmware type**. Для этой схемы установки оставьте Secure Boot выключенным. В **Hardware → Display** включите **Accelerate 3D graphics**. Проверьте драйвер видеокарты на Windows, если Workstation сообщает, что 3D недоступно. Linux-гость будет использовать виртуальный SVGA-адаптер, который предоставляет Workstation. [Настройка 3D в Workstation](https://knowledge.broadcom.com/external/article/329348), [драйвер Mesa SVGA3D](https://docs.mesa3d.org/drivers/svga3d.html)

## 2. Установите чистую NixOS

Загрузитесь с ISO и запустите графический установщик. Выберите язык и раскладку. В выборе рабочего стола подойдёт **No desktop**. Можно также использовать **официальный Minimal ISO** и пройти консольную установку из руководства NixOS. Именно этот вариант владелец проверил в VMware. [Установка NixOS](https://nixos.org/manual/nixos/stable/#sec-installation)

В разделе разметки выберите новый виртуальный диск, сверив размер. При ручной разметке удобно выделить под FAT32 EFI System Partition около 1 ГиБ или больше, оставив место для нескольких поколений. При автоматической разметке проверьте объём EFI после установки. Создайте пользователя **vladik** с собственным паролем, предоставьте ему права администратора и завершите установку. После перезагрузки отключите ISO и войдите под этим пользователем. Если выбрали No desktop, вход будет через текстовую консоль.

Откройте терминал и убедитесь, что система запущена в UEFI, а корень и EFI смонтированы:

```bash
test -d /sys/firmware/efi && echo UEFI
findmnt /
findmnt -t vfat
lsblk -f
```

Сделайте снимок выключенной ВМ после чистой установки. Он сохраняет начальную систему и состояние виртуального диска перед переходом на GRUB.

## 3. Включите Flakes и клонируйте репозиторий

Выполняйте команды от пользователя гостя.

```bash
export NIX_CONFIG='experimental-features = nix-command flakes'
nix-shell -p git --run 'git clone https://github.com/MrKzya/NixOS-vladik.git'
cd NixOS-vladik
```

`nix-shell` предоставляет Git для клонирования. После перехода Git и поддержка Flakes войдут в систему через репозиторий. Переменная `NIX_CONFIG` действует для текущего терминала. При новом входе до первого применения задайте её снова.

## 4. Подключите аппаратные данные гостя

Сохраните файлы установщика в `/etc/nixos/`. Скопируйте в клон только аппаратный модуль:

```bash
cp /etc/nixos/hardware-configuration.nix hosts/vmware/hardware-configuration.local.nix
nano hosts/vmware/hardware-configuration.local.nix
```

Файл `hardware-configuration.local.nix` игнорируется Git. Его автоматически подхватит `hosts/vmware/hardware-configuration.nix`. Если копии от установщика нет, на уже загруженной установленной системе используйте `sudo nixos-generate-config --show-hardware-config > hosts/vmware/hardware-configuration.local.nix`.

Сверьте в локальном модуле `fileSystems`, `swapDevices` и `boot.initrd` с фактической машиной. Должны совпасть корневой том, ESP и реальные устройства. Конфигурация ожидает ESP типа `vfat` и по умолчанию ищет её под `/boot`. Если `findmnt -t vfat` показывает, что отдельная ESP смонтирована в `/boot/efi`, добавьте в тело локального модуля:

```nix
boot.loader.efi.efiSysMountPoint = "/boot/efi";
```

Сверьте свободное место в найденной точке монтирования через `df -h`. Проверьте, что UUID и типы в файле относятся к диску гостя. Если на ISO был выбран выпуск с другим `system.stateVersion`, найдите исходное значение в `/etc/nixos/configuration.nix` и добавьте для этой машины `system.stateVersion = lib.mkForce "…";` в локальный модуль, подставив это значение. Стандартный сгенерированный модуль уже принимает `lib`.

В `#vmware` загрузчик, NetworkManager, Ly, графические сеансы и пользователь заданы модулями проекта. Оставьте `/etc/nixos/configuration.nix` для восстановления. Сборка по `#vmware` его не импортирует. Если при установке выбрали другое имя пользователя, укажите `mySystem.user` с этим именем в том же локальном модуле. Пароль, который вы задали в установщике, сохранится. Для смены пароля используйте `passwd` внутри гостя. Пароль и его хеш хранит установленная система.

## 5. Соберите и примените

Из корня клона выполните сначала сборку. Префикс `path:` позволяет Nix прочитать игнорируемый локальный аппаратный файл. В каталоге клона храните только исходники и локальные параметры, нужные для вычисления конфигурации. Nix копирует исходное дерево в Store.

```bash
flake="path:$PWD#vmware"
nixos-rebuild build --flake "$flake"
```

Если прошло успешно, запишите новое поколение в загрузчик **внутри гостевой ВМ**:

```bash
sudo env NIX_CONFIG="$NIX_CONFIG" nixos-rebuild boot --flake "$flake" --install-bootloader
sudo reboot
```

`boot` готовит следующее включение и сохраняет текущий сеанс до перезагрузки. Флаг для установки загрузчика нужен при первоначальном переходе на GRUB с загрузчика чистой NixOS. Для следующих обновлений этой ВМ достаточно той же команды без `--install-bootloader`.

GRUB показывает поколение системы. По умолчанию Ly на tty2 предлагает Niri. Чтобы добавить Plasma, включите `mySystem.desktop.plasma.enable` в `hosts/vmware/configuration.nix` и примените конфигурацию. После выхода из сеанса можно выбрать другой рабочий стол в Ly. При выключенных Niri и Plasma система загружается в TTY.

Если новое поколение не работает, загрузите прежнее из подменю GRUB. Если GRUB вообще не появляется, используйте меню прошивки ВМ **Power On to Firmware** и выберите исходную запись UEFI, если она доступна, либо восстановите снимок. Из работающего гостя можно выполнить `sudo nixos-rebuild boot --rollback`. [Откаты NixOS](https://nixos.org/manual/nixos/stable/#sec-rollback)

## 6. Проверьте графику и VMware Tools

| Проверка | Что посмотреть |
| --- | --- |
| Гостевая служба | `systemd-detect-virt` должен показать `vmware`. В любом профиле выполните `systemctl status vmware.service` и `vmtoolsd --version`. |
| Niri | После входа выполните `systemctl --user status niri.service dms.service vicinae.service` и `niri msg outputs`. Проверьте панель DMS, Alt+Space и меню блокировки. |
| Plasma, если включена | После входа `echo "$XDG_SESSION_TYPE"` покажет `wayland`. Проверьте разрешение в настройках дисплея. Доступность Vulkan в VMware зависит от виртуального GPU. |
| TTY, если выключены оба окружения | `systemctl get-default` должен показать `multi-user.target`. |

Если для Vicinae раньше добавляли временный пользовательский drop-in с `PATH`, после обновления удалите из него эту строку. Посмотреть источник настройки можно через `systemctl --user cat vicinae.service`. Затем выполните `systemctl --user daemon-reload` и `systemctl --user restart vicinae.service`. Проверьте запуск Firefox и VS Code из Alt+Space и журнал `journalctl --user -b -u vicinae.service`.

В закреплённом Nixpkgs VMware-гость включает системный `vmtoolsd` из `open-vm-tools-headless`. Видеоустройство VMware обслуживает модуль ядра `vmwgfx`, а графические профили используют Mesa с драйвером `svga`. Мышь в Wayland обслуживается стандартным вводом ядра и композитора. Если указатель остался захвачен VMware, используйте сочетание освобождения ввода Workstation, обычно Ctrl+Alt. [Модуль NixOS VMware](https://github.com/NixOS/nixpkgs/blob/2786a2a72088ecf32aea5b3ec52099e6a7cff78f/nixos/modules/virtualisation/vmware-guest.nix), [Mesa SVGA3D](https://docs.mesa3d.org/drivers/svga3d.html)

Для Niri откройте `hosts/vmware/niri/display.kdl` и задайте выход и режим из `niri msg outputs`, если автоматический результат не подходит. Затем пересоберите поколение. Автоподстройка под размер окна Workstation зависит от гостевой графики и композитора. Буфер обмена внутри гостя работает средствами сеанса. Для общего буфера Windows ↔ Linux и drag-and-drop Broadcom указывает ограничение в Wayland. Включение Guest Isolation в Workstation само по себе его не снимает. [Ограничения буфера обмена и drag-and-drop](https://knowledge.broadcom.com/external/article/320995)

## 7. Если Niri не запускается

1. Переключитесь на tty1 или загрузите рабочее поколение. На выключенной ВМ проверьте включённое 3D, поддержку у драйвера Windows и наличие виртуального дисплея.
2. После попытки входа проверьте модули, устройства и журналы внутри гостя:

   ```bash
   lsmod | grep vmwgfx
   ls -l /dev/dri/
   sudo journalctl -b -k | grep -Ei 'vmwgfx|drm|svga'
   sudo journalctl -b -u display-manager.service -u vmware.service
   journalctl --user -b -u niri.service -u dms.service
   ```

3. Для проверки EGL из графического сеанса используйте `nix shell nixpkgs#mesa-demos -c eglinfo -B`. Ищите сведения о Wayland и GBM. `llvmpipe` означает программный рендеринг. Запись об SVGA3D подтверждает путь VMware для проверенного контекста. Если включена Plasma, отдельно проверьте её сеанс.
4. При чёрном экране сохраните журналы, отключите 3D на один диагностический запуск чистой NixOS или Plasma и сравните результат. Владелец подтвердил работу Niri + DMS после чистой установки NixOS 26.05 в VMware. Автоподстройка разрешения и игры требуют отдельной проверки.

## Переход рабочей VMware на V2

1. Сохраните снимок выключенной ВМ. В существующей системе проверьте `hosts/vmware/hardware-configuration.local.nix` и сохраните его резервную копию вне репозитория. Пользователь, пароль, домашний каталог и DMS остаются в установленной системе. Чтобы в период проверки не сработало автоматическое удаление поколений, временно задайте в локальном модуле `nix.gc.automatic = false;`.
2. До перехода запишите путь активной системы и размер её замыкания. Если сейчас загружена специализация, отдельно измерьте родительское поколение из `/nix/var/nix/profiles/system` — именно оно удерживает все специализации V1.

   ```bash
   old=$(readlink -f /nix/var/nix/profiles/system)
   nix path-info --closure-size --human-readable "$old"
   sudo nix-store --add-root /nix/var/nix/gcroots/nixos-vladik-pre-v2 --realise "$old"
   git pull --ff-only origin main
   ```

3. Просмотрите `hosts/vmware/configuration.nix`. Если старый локальный модуль задавал `mySystem.development`, `binaryCompatibility` или `networkApps`, перенесите их в актуальные флаги из [COMPONENTS.md](COMPONENTS.md). Оставьте прежние имя пользователя, точку ESP, корень и `system.stateVersion`.

   ```bash
   nixos-rebuild build --flake "path:$PWD#vmware"
   nix path-info --closure-size --human-readable ./result
   sudo nixos-rebuild boot --flake "path:$PWD#vmware"
   sudo reboot
   ```

4. После загрузки проверьте Ly, Niri, DMS и Vicinae, пароль и содержимое домашнего каталога. Старое поколение можно выбрать в GRUB. Флаг `--install-bootloader` при обычном переходе с уже работающего GRUB не нужен. Сравнение двух `path-info` показывает размер двух реализованных замыканий; оно не измеряет освобождение места на диске. Физическое использование можно сравнить `df -h /nix` до и после GC.
5. Только после проверки выполните `sudo nix-env --profile /nix/var/nix/profiles/system --list-generations`. При необходимости удалите **выбранные старые** поколения через `sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations НОМЕР`. Номера активного и сохранённых рабочих поколений оставьте. Обновите меню GRUB через `nixos-rebuild boot`. Когда сохранённый V1 больше не нужен, удалите созданную на шаге 2 ссылку `/nix/var/nix/gcroots/nixos-vladik-pre-v2`, затем выполните `sudo nix store gc`. Если старая сборка остаётся в Store, проверьте другие GC roots, в том числе ссылки `result*`. Пользовательские библиотеки игр, кэш и Flatpak очищаются отдельно. После проверки можно вернуть еженедельную очистку, удалив локальное переопределение.

Для локальных проверок из корня клона:

```bash
nix build --no-link "path:$PWD#checks.x86_64-linux."{components,desktop-matrix,niri-vmware,niri-optional-bindings,shell-config}
nixos-rebuild build --flake "path:$PWD#vmware"
```

`nix flake check --no-build --keep-going "path:$PWD"` также вычисляет остальные хосты. В чистом клоне VMware, ThinkPad и MacBook ожидают локальных данных дисков. В установленной VMware проверяй полный конфиг именно своего гостя.
