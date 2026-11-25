# MacBook Air 2020 с Apple T2

Целевая модель — `MacBookAir9,1`, Intel Core i3-1000NG4, 8 ГиБ RAM и экран 2560 × 1600. Профиль поддерживает распознавание других Intel MacBook с T2. Ввод и накопитель на Air подтверждены владельцем в Live с ядром 6.18.35. Загрузка V3 и работа периферии в установленной системе требуют отдельной проверки.

## Подготовка

Модель в macOS определяется командой `sysctl -n hw.model`, разметка — `diskutil list internal physical`. Перед изменением разметки требуется проверенная резервная копия Time Machine. Место под Linux выделяется через Disk Utility с сохранением APFS, Recovery и Apple ESP. [Time Machine](https://support.apple.com/en-us/104984), [Разметка диска T2](https://wiki.t2linux.org/guides/preinstall/#partition-with-disk-utility)

Подходящий образ — `t2-iso-minimal`. В macOS Recovery параметры Startup Security Utility для загрузки Linux — **No Security** и **Allow booting from external or removable media**. Они отключают проверку подписей загрузки Intel CPU и допускают загрузку с внешнего носителя. Live загружается через удержание Option и выбор EFI Boot на USB. Перед разметкой в Live проверяются ввод, накопитель и сеть. При отсутствии Wi-Fi подходит USB-Ethernet. [Startup Security Utility](https://support.apple.com/en-us/102522), [T2 ISO](https://github.com/t2linux/nixos-t2-iso)

## Защита dual boot

Установщик ищет Apple ESP, APFS и отдельный Linux ESP на том же GPT-накопителе, где находится корень NixOS. Порядок определяется по начальным секторам, идентификаторы — по реальным PARTUUID. При дополнительных ESP или неоднозначности установка останавливается. Linux ESP должен быть пуст при первой установке. `/boot` проверяется перед установкой GRUB, в том числе штатной проверкой модуля Apple T2. GRUB работает в режиме removable fallback и пишет только в Linux ESP. Запись в NVRAM и OS Prober отключены.

В меню Option внутренний Linux ESP появляется как **EFI Boot**. macOS остаётся системой по умолчанию, если её загрузочный диск был выбран ранее. Проверка включает загрузку NixOS через Option, загрузку macOS через Option и обычный запуск без клавиш.

## Firmware и первое включение

Пункт Firmware Broadcom принимает предварительно подготовленные t2linux-файлы из `/lib/firmware/brcm` в Live или образ Apple Recovery (`sonoma`, `ventura`, `monterey`). Вариант Recovery использует закреплённый модуль nixos-hardware и хеш источника. Вариант Live копирует только соответствующие файлы в игнорируемый каталог хоста. Установщик не запускает способы извлечения, которые монтируют Apple ESP и могут записывать туда файлы. Подготовка из собственной macOS на внешнем носителе описана в документации t2linux. При выборе `none` доступность встроенного Wi-Fi и Bluetooth зависит от наличия подходящего firmware. [Wi-Fi и Bluetooth](https://wiki.t2linux.org/guides/wifi-bluetooth/), [NixOS T2](https://wiki.t2linux.org/distributions/nixos/installation/#wi-fi-and-bluetooth-setup)

Проверки после загрузки включают клавиатуру в initrd, тачпад, `wpctl status`, `bluetoothctl show`, `brightnessctl -l`, температуру, сон и повторное пробуждение. Масштаб Niri 1,75 и ZRAM около 4 ГиБ остаются настройками для испытаний на `MacBookAir9,1`. Для ZRAM можно отдельно проверить `zramSwap.enable = true;` и `zramSwap.memoryPercent = 50;` на этом хосте. Фактический выход дисплея определяется через `niri msg outputs`; устройство и масштаб задаются в `hosts/macbook/niri/display.kdl`. [Матрица оборудования](https://wiki.t2linux.org/state/)

При отказе загрузки macOS доступна через Option. Для диагностики Linux используется тот же T2 Live без форматирования и с монтированием только подтверждённых Linux-разделов. [Бинарный кеш](BINARY-CACHE.md) · [Диагностика](TROUBLESHOOTING.md)
