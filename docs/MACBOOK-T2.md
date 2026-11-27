# MacBook Air 2020 с Apple T2

Целевая модель `MacBookAir9,1` использует Core i3-1000NG4, 8 ГиБ RAM, Intel Iris Plus и экран 2560 × 1600. Владелец установил V3.1 с NixOS 26.11, Niri 26.04 и подписанным ядром 6.18.35 с `apple-bce`. На этом ядре он проверил ручной suspend, сон при закрытии крышки и пробуждение при её открытии. После открытия крышки наблюдалась небольшая задержка. [Ядро и кеш](BINARY-CACHE.md)

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

V3.2 включает подтверждённый suspend и действие крышки на батарее и от зарядки. Уберите временные переопределения `sleep.conf` и `logind.conf`, если они остались от ручного теста. DMS управляет DPMS через Niri, блокировкой и таймерами, а logind обрабатывает закрытие крышки. Для диагностики аппаратного сбоя установите `mySystem.laptopPower.suspend.enable = false;` в локальном модуле и пересоберите систему. Это выключит suspend и действие крышки, сохранив таймеры дисплея и блокировки. [Значения таймеров](CONFIGURATION.md#питание-ноутбука)

```bash
cat /sys/power/mem_sleep
cat /proc/acpi/wakeup
systemctl suspend
sudo journalctl -b -k | grep -Ei 'apple.bce|t2bce|vhci|brcmfmac|PM:|HID'
```

Для обоих доступных режимов записываются время появления картинки, время возврата ввода, способ пробуждения и расход батареи за сопоставимый интервал. Проверяются повторные циклы и Enter в пустом терминале. Доступные режимы можно переключать для отдельного теста через `systemd.sleep.settings.Sleep.MemorySleepMode` в локальном модуле.

## Клавиатура и дисплей

`mySystem.macbook.macOSKeybindings.enable` включает сочетания Command в Niri. xremap применяет сочетания вкладок и навигации к известным ID приложений. В графических приложениях редактирование остаётся на Ctrl. В Kitty `Ctrl+C/D/Z/L/R` передаются терминалу, `Ctrl+Shift+C/V` копируют и вставляют, а Cmd+T/W управляют вкладками Kitty.

| Клавиши | Действие |
| --- | --- |
| Cmd+Space, Cmd+Enter, Cmd+Q | Vicinae, Kitty, закрытие окна |
| Cmd+Tab, Cmd+Shift+Tab | Недавние окна Niri |
| Cmd+T/W/Shift+T, Cmd+L/R/Shift+R, Cmd+N/O | Вкладки, адрес, обновление и открытие в браузере. В VS Code и Obsidian используются применимые сочетания |
| Cmd+Alt+L/T/W/O/Tab | Прежние команды Niri, освобождающие сочетания для приложений |
| F1/F2, F5/F6 | Яркость дисплея и подсветка клавиатуры по разным шкалам. Удержание повторяет шаги |
| F7–F12 | Управление проигрывателем и звуком |

На `eDP-1` установлен масштаб **1.6**. Разрешение и частота берутся из предпочтительного режима EDID. Для экрана входа Ly загружает Terminus 16×32 в свою TTY. Яркость регулируется в аппаратных единицах `intel_backlight` и `:white:kbd_backlight`. F2 возвращает дисплей с 0 на 1%. Движение мыши восстанавливает автоматически погашенную подсветку клавиатуры, ручной ноль сохраняется. `mySystem.macbook.keyboardBacklight.idle.enable` отключает 60-секундный таймер подсветки клавиатуры отдельно от DPMS. `mySystem.macbook.zram.enable` добавляет ZRAM с логическим пределом 50% RAM и по умолчанию выключен.

Владелец подтвердил `KEY_FN` (464, `MSC_SCAN ff0003`). Udev создаёт `/dev/input/macbook-internal-keyboard` для интерфейса с клавишами Fn, A и Space. `eventN` может поменяться после пробуждения. Короткое одиночное нажатие Fn выдаёт `F24`, удержание и сочетания сохраняют исходный Fn. Alt+Shift остаётся запасным переключателем. `macOSKeybindings.fnKey = null` отключает переназначение Fn. Для диагностики используйте журнал и, при необходимости, `evtest` после остановки xremap. [Niri IPC в xremap](https://github.com/xremap/xremap/blob/v0.15.18/doc/running_with_sudo.md)

```bash
readlink -e /dev/input/macbook-internal-keyboard
journalctl --user -b -u macbook-shortcuts.service
systemctl --user stop macbook-shortcuts.service
sudo nix shell nixpkgs#evtest -c evtest
systemctl --user reset-failed macbook-shortcuts.service
systemctl --user start macbook-shortcuts.service
niri msg --json windows
niri msg outputs
```

В Niri 26.04 длина горизонтального свайпа зашита в алгоритме движения и выбора точки остановки. `mySystem.macbook.adjacentSwipe.enable = true;` включает экспериментальный патч этой же версии. Он ускоряет трёхпальцевый горизонтальный свайп и ограничивает итог соседней колонкой в обычном режиме. Включение требует сборки Niri. Двухпальцевая прокрутка, вертикальные жесты и переключение в обзоре остаются в штатном режиме. [Жесты Niri](https://github.com/niri-wm/niri/wiki/Configuration%3A-Gestures)

После перехода на V3.2 проверьте блокировку перед сном, таймеры на обоих источниках питания, Fn после пробуждения, удержание клавиш яркости, восстановление обоих ручных уровней и читаемость Ly. Ручной suspend и открытие крышки проверены владельцем на V3.1. Поведение Wi‑Fi BCM4377, Bluetooth и экспериментального жеста требует отдельного прогона.
