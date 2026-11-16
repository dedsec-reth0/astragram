# Сторонние компоненты и лицензии

AstraGram — форк [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS). Исходный код Telegram-iOS
опубликован под GNU GPL версии 2. AstraGram распространяется на тех же условиях; полный текст лицензии лежит в файле
[LICENSE](LICENSE). Авторские уведомления в исходных файлах Telegram сохранены. Название и логотип Telegram
принадлежат их владельцу, AstraGram не связан с Telegram.

## Исходный код сборок

Каждая сборка в [релизах](https://github.com/dedsec-reth0/astragram/releases) собрана GitHub Actions из открытого
коммита этого репозитория (`v13.2-<сборка>` указывает на него). Исходный код любой опубликованной сборки можно получить
из этого репозитория по тегу релиза вместе с подмодулями (`git clone --recursive`).

## Компоненты

Ниже перечислены основные сторонние библиотеки, которые входят в приложение. Лицензия каждой определяется файлом
лицензии в её каталоге (или в её исходном репозитории для подмодулей) — он имеет приоритет над этим списком.

| Компонент | Где в репозитории | Лицензия |
| --- | --- | --- |
| Telegram-iOS | весь репозиторий | GPL-2.0 |
| TDLib | `third-party/td` | Boost Software License 1.0 |
| WebRTC | `third-party/webrtc` | BSD-3-Clause (Abseil — Apache-2.0) |
| tgcalls | `submodules/TgVoipWebrtc/tgcalls` | см. исходный репозиторий подмодуля |
| BoringSSL | `third-party/boringssl` | OpenSSL / ISC и др., см. `third-party/boringssl/LICENSE` |
| libvpx | `third-party/libvpx` | BSD-3-Clause |
| dav1d | `third-party/dav1d` | BSD-2-Clause |
| OpenH264 | `third-party/openh264` | BSD-2-Clause |
| Opus, libogg, opusfile | `third-party/opus`, `ogg`, `opusfile` | BSD-3-Clause |
| RNNoise | `third-party/rnnoise` | BSD-3-Clause |
| libyuv | `third-party/libyuv` | BSD-3-Clause |
| libwebp | `third-party/webp` | BSD-3-Clause |
| libjxl | `third-party/libjxl` | BSD-3-Clause |
| mozjpeg | `third-party/mozjpeg` | IJG, BSD-3-Clause, zlib (см. `LICENSE.md`) |
| FlatBuffers | `third-party/flatc` | Apache-2.0 |
| Boost.Regex | `third-party/boost_regex` | Boost Software License 1.0 |
| Gumbo | `third-party/gumbo` | Apache-2.0 |
| WAMR | `third-party/wamr` | Apache-2.0 с LLVM exception |
| QuickJS-ng (движок плагинов) | `third-party/quickjs-ng` | MIT |
| SwiftMath | `third-party/SwiftMath` | MIT |
| XMLCoder | `third-party/XMLCoder` | MIT |
| ZipArchive / minizip | `third-party/ZipArchive` | MIT / zlib |
| twidget | `third-party/twidget` | BSD-3-Clause |
| web-platform-tests | `third-party/wpt` | BSD-3-Clause |
| Yasm (только для сборки) | `third-party/yasm` | см. `third-party/yasm/yasm-1.3.0/COPYING` |
| rlottie (tlottie) | `submodules/tlottie` | см. исходный репозиторий подмодуля |
| reCAPTCHA, Swift2D, libprisma, mtproto-engine, wallet-engine, subcodec, widget-sandbox | `third-party/…` | как в Telegram-iOS, см. их каталоги и исходные репозитории |

## Идеи из других клиентов

Режим призрака и сохранение удалённых сообщений сделаны по образцу поведения
[AyuGram Desktop](https://github.com/AyuGram/AyuGramDesktop) (GPL-3.0). Код AyuGram в AstraGram не копировался:
поведение повторено заново на Swift поверх кода Telegram-iOS.

Список составлен вручную и может быть неполным. Если вы нашли ошибку, откройте issue.
