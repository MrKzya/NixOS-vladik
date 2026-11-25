# NixOS рядом с macOS на Intel MacBook Pro с T2

Схема установки — GPT, существующий APFS и ESP macOS, новый корень Linux и отдельный новый ESP для Linux. NixOS кладёт GRUB/Minegrub на Linux ESP по пути `EFI/BOOT/BOOTX64.EFI`. Запуск — через Option (Alt) → EFI Boot. При обычном включении загрузочным диском остаётся macOS.

## 1. Определи модель и сделай резервную копию

В **macOS целевого MacBook** выполни:

```bash
uname -m
sysctl -n hw.model
diskutil list internal physical
diskutil apfs list
```

Нужен Intel `x86_64` и фактический идентификатор `MacBookPro…`. Сверь наличие T2 в «Информация о системе → Контроллер» и модель с таблицей совместимости. Сохрани карту разделов локально. Для сверки номера и PARTUUID исходного ESP выполни `diskutil info <раздел-ESP-macOS>` и запиши **Disk / Partition UUID**. Команды с полной информацией о системе могут вывести серийный номер, его не нужно записывать или публиковать. [Матрица поддержки t2linux](https://wiki.t2linux.org/state/)

Сделай резервную копию Time Machine и проверь, что важные файлы доступны для восстановления. Подготовь способ входа в macOS Recovery и данные для восстановления FileVault, если он используется. [Time Machine](https://support.apple.com/en-us/104984)

## 2. Освободи место под Linux

В macOS открой Disk Utility → View → Show All Devices. Выбери внутренний физический диск и используй **Partition**, чтобы уменьшить APFS-контейнер средствами macOS и создать временный раздел для Linux, например MS-DOS. Зафиксируй его положение и размер. ESP macOS, контейнер APFS, Recovery и другие существующие разделы сохраняются. При невозможности уменьшить APFS остановись и разбери ошибку Disk Utility. [Разметка t2linux](https://wiki.t2linux.org/guides/preinstall/#partition-with-disk-utility)

## 3. Подготовь T2 Live и разреши загрузку

1. Возьми **t2-iso-minimal** для x86-64 из релизов t2linux. Обычный официальный NixOS ISO может не поднять встроенный ввод и накопитель на T2. Проверь опубликованную контрольную сумму, если она есть. Если загрузочный образ отсутствует или ему не хватает поддержки модели, собери `.#packages.x86_64-linux.t2-iso-minimal` по инструкции проекта на доступном x86_64 Linux. [Проект образа](https://github.com/t2linux/nixos-t2-iso), [релизы](https://github.com/t2linux/nixos-t2-iso/releases)
2. Запиши ISO на USB через программу записи образов. Перед подтверждением сверь модель и размер **внешней флешки** в `diskutil list external physical`. Запись стирает содержимое выбранной флешки.
3. На Intel Mac войди в macOS Recovery через **Command+R**, открой Startup Security Utility, войди с учётной записью администратора macOS. Для неподписанного Linux выставь **No Security** и **Allow booting from external or removable media**. Это отключает проверку подписи загрузки на Intel CPU и разрешает загрузку со съёмных носителей. FileVault и пароль macOS настраиваются отдельно. Меняй политику вручную, если согласен с этим последствием. [Apple Startup Security Utility](https://support.apple.com/en-us/102522), [External Boot в t2linux](https://wiki.t2linux.org/guides/preinstall/#disable-secure-boot)
4. Включи Mac с зажатой **Option (Alt)** и выбери EFI Boot со значком USB. Отключать APFS или менять Startup Disk для этого не нужно.

В live-системе проверяй до разметки:

```bash
test -d /sys/firmware/efi && echo UEFI
cat /sys/class/dmi/id/product_name
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,PARTTYPE,PARTUUID,MOUNTPOINTS
lsmod | grep -E 'apple_bce|i915|brcm'
ip -br link
```

Проверь клавиатуру и выделение/движение пальца на тачпаде. На минимальном ISO движение низкоуровневых событий можно проверить через `libinput debug-events`, если утилита доступна. Если ввод не работает, подключи USB-клавиатуру и мышь. Если внутренний накопитель не виден или не совпадает с картой macOS, разметку откладывай до исправления Live. Подключись по USB-Ethernet либо совместимому USB-адаптеру. USB tethering может быть альтернативой, если адаптер определяется как сетевой интерфейс.

## 4. Firmware и аппаратные опции

Broadcom Wi-Fi и Bluetooth требуют firmware Apple. В штатном T2 ISO `get-apple-firmware` позволяет временно извлечь его из собственной macOS или образа восстановления Apple. Выбери метод по инструкции t2linux, учитывая доступность сети и версии macOS. При чтении macOS достаточно доступа на чтение. После запуска в Live `ip -br link` и `rfkill list` покажут интерфейсы и блокировки. [Wi‑Fi и Bluetooth](https://wiki.t2linux.org/guides/wifi-bluetooth/), [методы для NixOS](https://wiki.t2linux.org/distributions/nixos/installation/#wi-fi-and-bluetooth-setup)

Для установленной системы выбери один из путей:

- **Автоматически** через `hardware.apple-t2.firmware.enable = true;`. Установи `firmware.version` в `"sonoma"`, `"ventura"` или `"monterey"` после сверки модели с документацией. Закреплённый upstream извлекает файлы из образа Apple. Этот вариант требует сети, а пригодность firmware зависит от модели и доступности образа.
- **Локально**. После извлечения положи содержимое `/lib/firmware/brcm/` в `hosts/macbook/firmware/brcm/` в локальной копии проекта, включи `mySystem.macbook.localFirmware.enable`. Каталог по умолчанию игнорируется Git. Nix копирует firmware в системный Store, поэтому держи рядом только необходимые бинарники производителя. Этот путь не требует публикации firmware.

Остальные опции в `hosts/macbook/configuration.nix`:

| Узел | Настройка и что подтвердить |
| --- | --- |
| Ядро и ранний ввод | Закреплённый `nixos-hardware` включает T2 Linux `stable` и `apple-bce` в initrd. Тачпад и клавиатуру проверь в Live и после загрузки, жесты — в Niri |
| Touch Bar | После подтверждения панели можно включить `hardware.apple.touchBar.enable` для tiny-dfr |
| Звук | Upstream подключает конфигурацию T2 и патчи для PipeWire/WirePlumber. Сверь модель в инструкции audio и начни с наушников/USB-аудио или малой громкости при проверке динамиков |
| Графика и Retina | Mesa и i915 подхватываются по оборудованию. Оставь автоматический выбор дисплея до `niri msg outputs`; затем запиши `scale` в `hosts/macbook/niri/display.kdl`. `mySystem.macbook.intelMedia.enable` добавляет Intel VA-API после проверки GPU. `enableIGPU` в upstream относится к поддерживаемому случаю AMD dGPU |
| Вентиляторы и питание | Уточни датчики и кривые для модели, затем при необходимости настрой `services.t2fanrd`. Параметры IOMMU и сна задаёт upstream. Тестируй suspend/resume отдельно с сохранённой работой |
| Яркость и клавиши | Проверь `brightnessctl -l`, отдельные светодиодные устройства клавиатуры и привязки XF86. Названия устройств и поддержка зависят от модели |

[Модуль T2 из закреплённого nixos-hardware](https://github.com/NixOS/nixos-hardware/tree/ff49dbf39553717ac8e0f4d5085fa0ca10c1031f/apple/t2), [звук](https://wiki.t2linux.org/guides/audio/), [вентиляторы](https://wiki.t2linux.org/guides/fan/)

## 5. Создай разделы и подключи конфигурацию

В Live сверь `lsblk` с картой macOS и границами временного раздела. Можно использовать `parted <проверенный-диск> unit MiB print free` для просмотра, а затем `cfdisk` для изменения только отведённой области. Из временного раздела выдели **новый** GPT EFI System Partition, примерно 1–2 ГиБ, и отдельный Linux filesystem для корня. Просмотри таблицу до записи. При несовпадении границ отменяй операцию. APFS, исходный ESP macOS и прочие Apple-разделы должны присутствовать с прежними границами.

Форматирование выполняется только после повторной проверки карты дисков и GPT-типов. Следующий блок предполагает, что в переменных Bash уже указаны три проверенных пути **к разделам**. Используй для обоих ESP пути `/dev/disk/by-partuuid/…`. Для `LINUX_ROOT` укажи новый раздел Linux, например также через PARTUUID.

```bash
(
  set -eu
  root=$(readlink -e "${LINUX_ROOT:?укажи новый корневой раздел}")
  esp=$(readlink -e "${LINUX_ESP:?укажи новый Linux ESP}")
  mac=$(readlink -e "${MACOS_ESP:?укажи исходный ESP macOS}")
  test "$root" != "$esp"
  test "$root" != "$mac"
  test "$esp" != "$mac"
  test "$(lsblk -dn -o TYPE "$root")" = part
  test "$(lsblk -dn -o TYPE "$esp")" = part
  test "$(lsblk -dn -o TYPE "$mac")" = part
  test "$(lsblk -dn -o PARTTYPE "$root")" = 0fc63daf-8483-4772-8e79-3d69d8477de4
  test "$(lsblk -dn -o PARTTYPE "$esp")" = c12a7328-f81f-11d2-ba4b-00a0c93ec93b
  test "$(lsblk -dn -o PARTTYPE "$mac")" = c12a7328-f81f-11d2-ba4b-00a0c93ec93b
  if findmnt -rn -S "$root" || findmnt -rn -S "$esp"; then exit 1; fi
  lsblk -o PATH,SIZE,TYPE,FSTYPE,PARTTYPE,PARTUUID,MOUNTPOINTS "$root" "$esp" "$mac"
  read -r -p 'Сверь три раздела. Для форматирования новых двух введи FORMAT-LINUX: ' confirmed
  test "$confirmed" = FORMAT-LINUX
  sudo mkfs.ext4 "$root"
  sudo mkfs.fat -F 32 "$esp"
)
```

Затем смонтируй **только Linux** корень и ESP, сгенерируй конфигурацию и клонируй репозиторий:

```bash
sudo mount "${LINUX_ROOT:?}" /mnt
sudo mkdir -p /mnt/boot /mnt/etc/nixos
sudo mount "${LINUX_ESP:?}" /mnt/boot
findmnt -M /mnt -o SOURCE,FSTYPE,TARGET
findmnt -M /mnt/boot -o SOURCE,FSTYPE,TARGET
sudo git clone --branch main https://github.com/MrKzya/NixOS-vladik.git /mnt/etc/nixos/NixOS-vladik
cd /mnt/etc/nixos/NixOS-vladik
sudo sh -c 'nixos-generate-config --root /mnt --show-hardware-config > hosts/macbook/hardware-configuration.local.nix'
sudo nano hosts/macbook/hardware-configuration.local.nix
```

В локальном файле оставь сгенерированную конфигурацию корня и initrd. У существующего `fileSystems."/boot"` замени `device` на PARTUUID **Linux ESP** и сверь `fsType = "vfat";`. В тело модуля добавь следующие поля, подставив оба пути со своей карты:

```nix
mySystem.macbook.linuxEsp = "/dev/disk/by-partuuid/<PARTUUID-Linux-ESP>";
mySystem.macbook.macosEsp = "/dev/disk/by-partuuid/<PARTUUID-macOS-ESP>";
boot.loader.grub.efiInstallAsRemovable = true;
```

Файл должен содержать два разных реальных PARTUUID. Nix проверяет их и разрешает только один EFI-установочный путь `/boot` без записи NVRAM. Проверка перед `boot` или `switch` сравнивает фактически смонтированное блочное устройство с подтверждённым Linux ESP до выполнения GRUB. При ошибке проверь карту и монтирование. Если Git недоступен в Live, получи его через `nix-shell -p git` или перенеси локальную копию репозитория с `flake.lock` на второй USB.

## 6. Установи NixOS и проверь обе загрузки

В корне клона из T2 Live ещё раз сверь корень и ESP из предыдущего шага. Затем:

```bash
export NIX_CONFIG='experimental-features = nix-command flakes'
sudo env NIX_CONFIG="$NIX_CONFIG" nixos-install --root /mnt \
  --flake "path:$PWD#macbook" --no-root-passwd
sudo nixos-enter --root /mnt -c 'passwd vladik'
findmnt -M /mnt/boot -o SOURCE,FSTYPE,TARGET
sudo test -f /mnt/boot/EFI/BOOT/BOOTX64.EFI
```

Если задано другое `mySystem.user`, установи пароль именно ему. При ошибке установки сохрани вывод и исправь причину до перезагрузки. Если установленный в Live `nixos-install` не принимает `--flake`, а вычисление Flake доступно, сначала выполни `nix build --no-link --print-out-paths "path:$PWD#nixosConfigurations.macbook.config.system.build.toplevel"` и укажи выведенный путь в `nixos-install --root /mnt --system <путь> --no-root-passwd`. Если Live слишком стар для вычисления, используй более свежий T2 ISO или собери рекомендованный Live на x86_64 Linux. [Установка из Flake в t2linux](https://wiki.t2linux.org/distributions/nixos/installation/#installation)

Выключи Mac, извлеки USB. В Option выбери **EFI Boot** внутреннего Linux ESP и проверь NixOS. Затем перезагрузись и отдельно выбери macOS в Option, после чего проверь обычное включение без Option. После загрузки Linux проверь:

```bash
uname -r
lsmod | grep -E 'apple_bce|i915|brcm'
journalctl -b -k | grep -Ei 'apple.bce|brcm|i915|firmware'
findmnt -M /boot
brightnessctl -l
wpctl status
bluetoothctl show
niri msg outputs
```

Проверь клавиатуру при ранней загрузке, тачпад, сеть, Bluetooth, звук, яркость, подсветку клавиш, температуру, Touch Bar при наличии и сон отдельно. Текущий компьютер разработки — arm64. Точные модель Intel MacBook, GPU, происхождение обоих ESP, фактический размер дисплея и работа периферии остаются проверками на целевой машине.

При неудачной загрузке выбери macOS через Option. Для ремонта Linux загрузи совместимый Live, смонтируй Linux корень и **только** подтверждённый Linux ESP. В GRUB можно сначала попробовать предыдущее поколение. Для ремонта системы переустанови её на те же смонтированные Linux разделы из проверенной ревизии через `nixos-install` без форматирования. Проверку реального монтирования оставь включённой. Исходная загрузка macOS сохраняется отдельно от GRUB.
