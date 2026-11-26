# MacBook Air 2020 с Apple T2

Целевая модель — `MacBookAir9,1`, Core i3-1000NG4, 8 ГиБ RAM, Intel Iris Plus, экран 2560 × 1600 при 60 Гц. На этом MacBook владелец загрузил V2 с ядром 6.18.55 и стеком `t2bce`. Подтверждены Niri, DMS, Kitty, встроенная клавиатура, дисплей, Intel-графика, проводная сеть и ручное изменение подсветки клавиатуры. V3 использует подписанное 6.18.35 с `apple-bce`. Ввод и накопитель на нём работали в T2 Live. Загрузка V3 и поведение периферии требуют проверки. [Ядро и кеш](BINARY-CACHE.md)

## Подготовка и dual boot

Модель в macOS определяется командой `sysctl -n hw.model`, разметка — `diskutil list internal physical`. Перед выделением места через Disk Utility требуется проверенная резервная копия Time Machine. Apple ESP, APFS и Recovery сохраняются. Используется `t2-iso-minimal`. В macOS Recovery штатные настройки для загрузки Linux — **No Security** и **Allow booting from external or removable media**. Они отключают проверку подписи загрузки Intel CPU и разрешают запуск со съёмного носителя. Live запускается через Option. При неработающем Wi‑Fi подходит USB-Ethernet. [Time Machine](https://support.apple.com/en-us/104984) · [Startup Security Utility](https://support.apple.com/en-us/102522) · [Подготовка T2](https://wiki.t2linux.org/guides/preinstall/)

Установщик проверяет два ESP и APFS на том же GPT-диске, что и корень NixOS. Запись идёт в отдельный Linux ESP после проверки реальных PARTUUID, типа GPT и монтирования `/boot`. GRUB устанавливает `EFI/BOOT/BOOTX64.EFI` без записи NVRAM и OS Prober. В проверке внутри `nixos-enter` типы читаются напрямую через `lsblk --properties-by blkid`. После установки проверяются Linux через **EFI Boot** в Option, macOS через Option и обычная загрузка macOS. [Установка](INSTALLATION.md)

## Broadcom BCM4377

Установщик оставляет firmware выключенной по умолчанию. Для этого Air первый вариант аппаратного теста — `archive` из установленной macOS Sequoia. В поддерживаемом скрипте t2linux для macOS используется режим **Create a tarball**. Полученный `firmware.tar` хранится на внешнем носителе и указывается в меню установщика. Этот способ получает файлы с собственной системы без записи на Apple ESP или APFS из Linux. Для импорта проверяются `brcmfmac4377b3-pcie.apple,formosa*` с Wi‑Fi `.bin` и NVRAM `.txt`, подходящие CLM/txcap и отдельные Bluetooth `brcmbt4377b3-apple,formosa*`. Об отсутствии CLM или Bluetooth-файла выводится сообщение. [Извлечение t2linux](https://wiki.t2linux.org/guides/wifi-bluetooth/) · [Исходник PCIe-драйвера 6.18.35](https://github.com/gregkh/linux/blob/v6.18.35/drivers/net/wireless/broadcom/brcm80211/brcmfmac/pcie.c)

Допустимы `live` для готовых файлов из `/lib/firmware/brcm` и варианты Apple Recovery `sonoma`, `ventura`, `monterey`. Recovery использует закреплённый рецепт nixos-hardware. Sonoma ранее поднимала интерфейс V2, но соединение завершалось ошибками сканирования и WPA. Ventura и Monterey остаются отдельными сравнительными тестами. Импортированные файлы лежат в игнорируемом `hosts/macbook/firmware/brcm`. [Firmware nixos-hardware](https://github.com/NixOS/nixos-hardware/tree/ff49dbf39553717ac8e0f4d5085fa0ca10c1031f/apple/t2/pkgs/brcm-firmware)

`mySystem.macbook.wifiBackend = "wpa_supplicant";` позволяет сравнить ассоциацию с исходным `iwd`. Ошибка командного кольца `brcmfmac` наблюдалась и с WPA Supplicant. Наличие SSID само по себе не подтверждает успешную передачу данных. Bluetooth проверяется отдельно по контроллеру, сканированию, сопряжению и аудио. [Отчёт BCM4377 о сбое командного кольца](https://github.com/t2linux/kernel/issues/32)

```bash
lspci -nnk | grep -A3 -Ei 'network|bluetooth'
sudo journalctl -b -k | grep -Ei 'brcmfmac|hci_bcm4377|firmware'
nmcli device wifi list
nmcli --ask device wifi connect "$SSID"
curl --fail --max-time 10 https://cache.nixos.org/nix-cache-info
bluetoothctl show
```

## Сон и пробуждение

В V2 тайм-аут D3 у BCM4377 прерывал suspend. Без проблемной firmware `deep` восстанавливался после открытия крышки с задержкой ввода, а `s2idle` быстро просыпался от кнопки и не просыпался от крышки. Расход батареи не измерен. Случай повторного появления Enter наблюдался и без Broadcom. Для нового `t2bce` отдельно задокументирован сбой восстановления VHCI при быстрых циклах S3. Эти данные не устанавливают причину Enter и не описывают поведение `apple-bce` в V3. [Отчёт о D3 и Bluetooth](https://github.com/omacom/omarchy/issues/11264) · [Регрессия VHCI](https://github.com/t2linux/kernel/issues/24)

Сопровождающий Broadcom принял общий патч, который допускает продолжение suspend после тайм-аута D3 ACK при выключенном Wake-on-WLAN. Специальный патч для BCM4377 заменён общим. В исходнике 6.18.35 и списке закреплённых T2-патчей этого исправления нет. Оно не лечит сбой командного кольца при активном Wi‑Fi. V3 не выгружает драйверы при suspend и не меняет ACPI wakeup. Для обратимого сравнения без Wi‑Fi существует `mySystem.macbook.blacklistBroadcomWifi = true;`. [Решение сопровождающего Broadcom](https://lore-kernel.gnuweeb.org/linux-wireless/20261004122824.1390579-1-arend.vanspriel%40broadcom.com/T/)

По умолчанию `mySystem.laptopPower.suspend.enable = false;` на MacBook. Для ручного теста с выключенными таймерами и сном от крышки в локальном Nix-модуле добавляется `systemd.sleep.settings.Sleep.AllowSuspend = lib.mkForce true;`. После подтверждения нескольких циклов достаточно убрать это переопределение и включить `mySystem.laptopPower.suspend.enable`. Режим сна V3 оставляет ядру.

```bash
cat /sys/power/mem_sleep
cat /proc/acpi/wakeup
systemctl suspend
sudo journalctl -b -k | grep -Ei 'apple.bce|t2bce|vhci|brcmfmac|PM:|HID'
```

Для обоих доступных режимов записываются время появления картинки, время возврата ввода, способ пробуждения и расход батареи за сопоставимый интервал. Проверяются повторные циклы и Enter в пустом терминале. Доступные режимы можно переключать для отдельного теста через `systemd.sleep.settings.Sleep.MemorySleepMode` в локальном модуле.

## Клавиатура и дисплей

`mySystem.macbook.macOSKeybindings.enable` включает профиль Command в Niri. Super, Ctrl и Alt сохраняют своё назначение. xremap получает события через разрешение для одного системного пользователя и применяет сочетания только к известным ID приложений. Kitty обрабатывает Cmd+C/V нативно. Ctrl+C/D/Z/L/R остаются сочетаниями терминала.

| Клавиши | Действие |
| --- | --- |
| Cmd+Space, Cmd+Enter, Cmd+Q | Vicinae, Kitty, закрытие окна |
| Cmd+Tab, Cmd+Shift+Tab | Недавние окна Niri |
| Cmd+C/V/X/A/Z/S/F | Редактирование в поддерживаемых графических приложениях |
| Cmd+T/W/Shift+T, Cmd+L/R/Shift+R, Cmd+N/O | Вкладки, адрес, обновление и открытие в браузере. В VS Code и Obsidian используются применимые сочетания |
| Cmd+Alt+L/C/T/F/W/O/Tab | Прежние команды Niri, освобождающие сочетания для приложений |
| F1/F2, F7–F12 | Стандартные события XF86 для дисплея, проигрывателя и звука |
| F5/F6 | Подсветка клавиатуры по 10%. DMS продолжает показывать штатный OSD для дисплея и звука |

На `eDP-1` установлен масштаб **1.6**. Разрешение и частота берутся из предпочтительного режима EDID. Внешние мониторы независимы. Параметр меняется в `hosts/macbook/niri/display.kdl`. `mySystem.macbook.keyboardBacklight.idle.enable` управляет 60-секундным таймером DMS. Ручной ноль сохраняется, предыдущий уровень восстанавливается после автоматического выключения. `mySystem.macbook.zram.enable` добавляет ZRAM с логическим пределом 50% RAM и по умолчанию выключен.

Для Fn сначала фиксируется фактическое событие встроенной клавиатуры на **6.18.35**, включая поведение при удержании. Затем параметрами `macOSKeybindings.fnKey` и `fnDevice` задаются подтверждённый код и имя или постоянный путь клавиатуры. Допустимы `KEY_FN` и `KEY_WAKEUP`. Пока оба параметра пустые, переключение RU/EN доступно через Alt+Shift. [Niri IPC в xremap](https://github.com/xremap/xremap/blob/v0.15.18/doc/running_with_sudo.md)

```bash
systemctl --user stop macbook-shortcuts.service
sudo nix shell nixpkgs#evtest -c evtest
systemctl --user start macbook-shortcuts.service
niri msg --json windows
niri msg outputs
```

После установки также проверяются динамики, микрофон, камера, Bluetooth-аудио, жесты тачпада, Intel-ускорение, яркость, зарядка, температура и вентилятор, USB, внешний монитор и разъём наушников. Пользовательский ввод, Wi‑Fi и пробуждение в V3 пока не подтверждены.
