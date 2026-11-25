# Ядро Apple T2 и бинарный кеш

## Закреплённая сборка

Профиль `macbook` использует Linux T2 **6.18.35** из T2 Live ISO. Ядро вычисляется со своим набором входов. Пользовательские пакеты, Home Manager и остальные профили используют основной Nixpkgs.

| Вход | Ревизия |
| --- | --- |
| T2 Live ISO, исходное окружение сборки | `063f2f581ffb96b6179dbf60dda3fceb0f6c438c` |
| `t2-kernel-nixpkgs` | `567a49d1913ce81ac6e9582e3553dd90a955875f` |
| `t2-kernel-hardware` | `875776f0252fcb8618bb948640a0d1f7a5b362be` |
| Основной `nixpkgs` | `2786a2a72088ecf32aea5b3ec52099e6a7cff78f` |
| Основной `nixos-hardware`, T2 initrd и звук | `ff49dbf39553717ac8e0f4d5085fa0ca10c1031f` |

Хеши входов закреплены в `flake.lock`. Для проверки подписей используется ключ `t2linux.cachix.org-1:P733c5Gt1qTcxsm+Bae0renWnT8OLs0u9+yfaK2Bejw=` из конфигурации T2 ISO. [T2 ISO и его lock-файл](https://github.com/t2linux/nixos-t2-iso/tree/063f2f581ffb96b6179dbf60dda3fceb0f6c438c)

## Результаты проверки

| Компонент | Путь Nix Store | Результат |
| --- | --- | --- |
| 6.18.35, образ ядра | `/nix/store/h38jyjhvrhmn0jyf6rf3rg6cxx7h79bd-linux-t2-6.18.35` | Cachix HTTP 200, скачан и проверен Nix |
| 6.18.35, дерево модулей | `/nix/store/6lgxdl1pjg4211sn897bvka14vzfcpsx-linux-t2-6.18.35-modules` | Cachix HTTP 200, скачан и проверен Nix |
| 6.18.35, `dev` | `/nix/store/fd3qv8pjsdcmb7nia29p578sgcdilbww-linux-t2-6.18.35-dev` | HTTP 404. Для штатной конфигурации не нужен |
| 6.18.35, ZFS из Live | `/nix/store/m2gcrmdqb6jfa6rz11h6zn48ifn3f2y6-zfs-kernel-2.4.3-6.18.35` | Cachix HTTP 200. Установленные профили не используют ZFS |
| 6.18.64, обычное ядро ThinkPad, VMware и QEMU | `/nix/store/qpbd6dabgk9zhg2i8f47shfkl89i5ag4-linux-6.18.64` | Подписанный narinfo в cache.nixos.org, HTTP 200 |
| 6.18.64 T2 из V2 | `/nix/store/vk34zvxq6vxyn0vf4rj28b2aa3x17gfq-linux-t2-6.18.64` | HTTP 404 во всех проверенных кешах |

Источники проверены 25 ноября 2026 г. Оба необходимых объекта 6.18.35 отсутствовали в `cache.soopy.moe` и `cache.nixos.org`, хотя оба сервера отвечали на `nix-cache-info`. Кеш Soopy упоминается в FAQ t2linux. Ядро 6.18.55 ранее не удалось получить по проверенному владельцем хешу. [FAQ t2linux](https://wiki.t2linux.org/distributions/nixos/faq/)

Скачанное дерево содержит `apple-bce`, `hid-apple`, `nvme`, `i915`, `brcmfmac`, `hci_bcm4377` и `btrfs`. NixOS собирает initrd с `apple-bce` на основе этих модулей. Варианты на стеке `t2bce` требуют пересмотра конфигурации ранней загрузки и собственной проверки бинарных объектов.

## Поведение установщика

Перед записью на целевой диск установщик вычисляет пути ядра, дерева модулей и внешних модулей выбранной конфигурации. Nix получает их из Live Store или доверенного кеша с `max-jobs=0`, пустым списком builders, выключенным fallback и обязательной проверкой подписей. Недоступный путь завершает этап ошибкой. Полученные объекты переносятся в целевой Store, где проверяется их регистрация. Этапы сборки системы и initrd используют уже полученное ядро. Cachix настроен и в установленном профиле MacBook.

Команды для независимой проверки

```bash
nix eval --json 'path:.#nixosConfigurations.macbook' --apply "$(cat installer/cache.nix)"
nix copy --from https://t2linux.cachix.org \
  --option require-sigs true \
  --option extra-trusted-public-keys 't2linux.cachix.org-1:P733c5Gt1qTcxsm+Bae0renWnT8OLs0u9+yfaK2Bejw=' \
  /nix/store/h38jyjhvrhmn0jyf6rf3rg6cxx7h79bd-linux-t2-6.18.35 \
  /nix/store/6lgxdl1pjg4211sn897bvka14vzfcpsx-linux-t2-6.18.35-modules
```

Обновление ядра требует повторной проверки точных выходов, подписей, initrd и загрузки. Если подписи и сборки исчезнут из публичного кеша, доступные локально объекты того же Flake могут быть подготовлены на x86_64 NixOS в VMware на мощной машине с Ryzen 9 9950X3D. Перенос возможен через локальный Nix Store или подписанный архив Nix с доверенным ключом. Постоянный частный кеш для этого варианта не требуется.
