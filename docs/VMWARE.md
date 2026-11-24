# NixOS-vladik в VMware Workstation на Windows

Сначала установите чистую NixOS с официального ISO. Затем подключите к репозиторию аппаратную конфигурацию установленного гостя и примените профиль `vmware`. В итоге Default, Gaming и Minimal будут загружаться из одного GRUB и использовать один диск и домашний каталог. Инструкция рассчитана на Windows на x86-64 и виртуальную машину Workstation.

## 1. Создайте виртуальную машину

1. На странице NixOS скачайте официальный **Graphical ISO, 64-bit Intel/AMD**. Для чистой установки подходит стабильный образ NixOS 26.05, соответствующий `system.stateVersion` проекта. GNOME или KDE можно выбрать в загрузочном меню ISO для live-среды. Рабочий стол установленной системы выбирается отдельно в установщике. [Скачать NixOS](https://nixos.org/download/)
2. В Workstation выберите **File → New Virtual Machine**. Создайте одну машину типа Linux x86-64. Если отдельного пункта NixOS нет, выберите **Other Linux 64-bit**. При предложении Easy Install создайте машину с вариантом **I will install the operating system later**, затем подключите скачанный ISO через **CD/DVD → Use ISO image file**.
3. Выделите **4 vCPU, 8 ГиБ RAM и 80 ГиБ** на новом расширяемом виртуальном диске. Это ориентир для сборки трёх профилей. Если планируете устанавливать игры, увеличьте диск с учётом их размера. Для первого теста достаточно NAT.
4. В настройках выключенной ВМ выберите **UEFI**. Обычно это **VM → Settings → Options → Advanced → Firmware type**. Для этой схемы установки оставьте Secure Boot выключенным. В **Hardware → Display** включите **Accelerate 3D graphics**. Проверьте драйвер видеокарты на Windows, если Workstation сообщает, что 3D недоступно. Linux-гость будет использовать виртуальный SVGA-адаптер, который предоставляет Workstation. [Настройка 3D в Workstation](https://knowledge.broadcom.com/external/article/329348), [драйвер Mesa SVGA3D](https://docs.mesa3d.org/drivers/svga3d.html)

## 2. Установите чистую NixOS

Загрузитесь с ISO и запустите графический установщик. Выберите язык и раскладку. В выборе рабочего стола подойдёт **No desktop**, тогда после установки вы получите TTY. Если хотите сначала проверить графику на стандартном окружении, выберите Plasma. Начальный рабочий стол сохранится в исходном поколении NixOS для отката. [Установка NixOS](https://nixos.org/manual/nixos/stable/#sec-installation)

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

В примере замените `ВЛАДЕЛЕЦ` на имя владельца публичного репозитория на GitHub. Выполняйте команды от пользователя гостя.

```bash
export NIX_CONFIG='experimental-features = nix-command flakes'
nix-shell -p git --run 'git clone https://github.com/ВЛАДЕЛЕЦ/NixOS-vladik.git'
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

В GRUB выберите **Default** для Niri, **Gaming** для Plasma Wayland или **Minimal** для входа в TTY. В Default и Gaming появится Ly на tty2. Войдите обычным паролем гостя.

Если новый режим не работает, загрузите **Minimal** или предыдущее поколение в подменю GRUB. Если GRUB вообще не появляется, используйте меню прошивки ВМ **Power On to Firmware** и выберите исходную запись UEFI, если она доступна, либо восстановите снимок. Из работающего гостя можно выполнить `sudo nixos-rebuild boot --rollback`, если нужен предыдущий системный профиль по умолчанию. [Откаты NixOS](https://nixos.org/manual/nixos/stable/#sec-rollback)

## 6. Проверьте графику и VMware Tools

| Проверка | Что посмотреть |
| --- | --- |
| Гостевая служба | `systemd-detect-virt` должен показать `vmware`. В любом профиле выполните `systemctl status vmware.service` и `vmtoolsd --version`. |
| Default | После входа из терминала выполните `systemctl --user status niri.service dms.service vicinae.service` и `niri msg outputs`. Проверьте панель DMS, Alt+Space и меню блокировки. |
| Gaming | После входа выполните `echo "$XDG_SESSION_TYPE"`. Ожидается `wayland`. Разрешение меняется в настройках дисплея Plasma. Откройте Steam и проверьте конкретную игру, если она важна. Поддержка Vulkan и Proton зависит от виртуального GPU и игры. |
| Minimal | Система стартует в консоль. Команда `systemctl get-default` должна показать `multi-user.target`. |

Если для Vicinae раньше добавляли временный пользовательский drop-in с `PATH`, после обновления удалите из него эту строку. Посмотреть источник настройки можно через `systemctl --user cat vicinae.service`. Затем выполните `systemctl --user daemon-reload` и `systemctl --user restart vicinae.service`. Проверьте запуск Firefox и VS Code из Alt+Space и журнал `journalctl --user -b -u vicinae.service`.

В закреплённом Nixpkgs VMware-гость включает системный `vmtoolsd` из `open-vm-tools-headless`. Видеоустройство VMware обслуживает модуль ядра `vmwgfx`, а графические профили используют Mesa с драйвером `svga`. Мышь в Wayland обслуживается стандартным вводом ядра и композитора. Если указатель остался захвачен VMware, используйте сочетание освобождения ввода Workstation, обычно Ctrl+Alt. [Модуль NixOS VMware](https://github.com/NixOS/nixpkgs/blob/2786a2a72088ecf32aea5b3ec52099e6a7cff78f/nixos/modules/virtualisation/vmware-guest.nix), [Mesa SVGA3D](https://docs.mesa3d.org/drivers/svga3d.html)

Для Niri откройте `hosts/vmware/niri/display.kdl` и задайте выход и режим из `niri msg outputs`, если автоматический результат не подходит. Затем пересоберите поколение. Автоподстройка под размер окна Workstation зависит от гостевой графики и композитора. Буфер обмена внутри гостя работает средствами сеанса. Для общего буфера Windows ↔ Linux и drag-and-drop Broadcom указывает ограничение в Wayland. Включение Guest Isolation в Workstation само по себе его не снимает. [Ограничения буфера обмена и drag-and-drop](https://knowledge.broadcom.com/external/article/320995)

## 7. Если Niri не запускается

1. Переключитесь на tty1 или загрузите Minimal. На выключенной ВМ проверьте включённое 3D, поддержку у драйвера Windows и наличие виртуального дисплея.
2. После попытки входа проверьте модули, устройства и журналы внутри гостя:

   ```bash
   lsmod | grep vmwgfx
   ls -l /dev/dri/
   sudo journalctl -b -k | grep -Ei 'vmwgfx|drm|svga'
   sudo journalctl -b -u display-manager.service -u vmware.service
   journalctl --user -b -u niri.service -u dms.service
   ```

3. Для проверки EGL из графического сеанса используйте `nix shell nixpkgs#mesa-demos -c eglinfo -B`. Ищите сведения о Wayland и GBM. `llvmpipe` означает программный рендеринг. Запись об SVGA3D подтверждает путь VMware для проверенного контекста. Отдельно проверьте, появляется ли изображение в Gaming. Это помогает отличить общую проблему SVGA от ошибки запуска Niri.
4. При чёрном экране сохраните журналы, отключите 3D на один диагностический запуск чистой NixOS или Plasma и сравните результат. Владелец подтвердил работу Niri + DMS в Default после чистой установки NixOS 26.05 в VMware. Автоподстройка разрешения и игры требуют отдельной проверки.
