<p align="center">
  <img src="assets/cover.png" alt="Four weather moods over a mountain lake" width="100%">
</p>

<h1 align="center">WeatherLoop</h1>

<p align="center">
  Живые видеообои для macOS, которые подстраиваются под погоду в выбранном городе.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-7d5fff" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-1f6feb" alt="macOS 14 or later">
</p>

<p align="center">
  <strong>Русский</strong> · <a href="#english">English</a>
</p>

WeatherLoop — небольшое приложение в строке меню. Для ясной, облачной, ночной и дождливой погоды назначаются локальные ролики, после чего приложение получает актуальные условия и бесшовно меняет видео на рабочем столе.

> [!IMPORTANT]
> В этом репозитории намеренно нет никаких видео. Выбранные ролики остаются на устройстве: приложение запоминает их пути, но не копирует и никуда не загружает.

## Что умеет

| | |
| --- | --- |
| 🌤️ Четыре сцены | Ясно, облачно, ночь и дождь/гроза — по одному ролику для каждого состояния. |
| 📍 Погода в нужном месте | Геопозиция macOS или город, заданный вручную. |
| 🔊 Полный контроль | Звук, пауза, продолжение, немедленное обновление и автозапуск. |
| 🖥️ Несколько экранов | Отдельное видеоокно создаётся на каждом подключённом дисплее. |
| 🔒 Локальные медиа | Видеофайлы остаются у пользователя; ключи API и аккаунт не нужны. |

## Быстрый старт

### Из готового релиза

1. В разделе Releases скачать `WeatherLoop-…-macOS-universal.zip`.
2. Распаковать архив и перенести `WeatherLoop.app` в папку «Программы».
3. Открыть приложение. При первом запуске macOS может попросить подтверждение, потому что сборки пока не подписаны и не нотарифицированы: нажать по приложению с зажатой `Control` → **Открыть**.

### Из исходников

Нужны macOS 14+ и Xcode Command Line Tools.

```sh
git clone <repository-url>
cd WeatherLoop
zsh build.sh
open WeatherLoop.app
```

### Настройка в приложении

1. Открыть меню WeatherLoop в строке меню.
2. В разделе **Видео для погоды…** указать локальные видео для всех четырёх сцен.
3. Задать город или разрешить геопозицию macOS.
4. Выбрать **Обновить погоду**. Сцена будет обновляться автоматически каждые 30 минут.

## Как это работает

Apple не даёт публичного API, который назначает любой MP4 системными динамическими обоями. Поэтому WeatherLoop создаёт неактивное видеоокно на уровне рабочего стола — над обычной картинкой обоев, но под иконками и приложениями.

Это означает две вещи:

- WeatherLoop должен оставаться запущенным, пока нужны видеообои. После выхода macOS тут же показывает прежние статичные обои.
- Это не «официальные видеообои macOS», а прозрачный и обратимый способ получить такой эффект без системных модификаций.

### Соответствие погоде

| Условие Open-Meteo | Сцена |
| --- | --- |
| Ясно / преимущественно ясно | `Ясно` |
| Облачно / туман | `Облачно` |
| Дождь / ливень / гроза / снег | `Дождь` |
| Ночь без осадков | `Ночь` |

## Приватность

Для прогноза WeatherLoop обращается напрямую к [Open-Meteo](https://open-meteo.com/en/docs). При ручном выборе города сервис получает его название, при геопозиции — координаты. Видео остаются локально, телеметрии и учётных записей нет.

## Для разработчиков

Ветка `main` проверяется GitHub Actions при каждом push и pull request. Чтобы выпустить версию, создай и отправь тег:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Workflow соберёт универсальный `.app` для Apple Silicon и Intel, упакует его в ZIP и создаст GitHub Release с заметками.

## Лицензия

Код распространяется по [лицензии MIT](LICENSE). Она относится только к WeatherLoop; права на свои видео и право их использовать проверяет сам пользователь.

<a id="english"></a>

---

## English

WeatherLoop is a small macOS menu-bar app that plays local videos as a weather-reactive desktop background. One video is assigned to each scene — clear, cloudy, night, and rain — then WeatherLoop checks current conditions and switches the video seamlessly.

> [!IMPORTANT]
> This repository deliberately contains no videos. Chosen media stays on the device: WeatherLoop saves local file paths only and never uploads or copies video files.

### Features

- Four weather scenes: clear, cloudy, night, and rain/thunderstorm.
- Weather from a manually selected city or macOS Location Services.
- Sound, pause/resume, manual refresh, login launch, and multiple displays.
- No account or API key. Weather is provided by Open-Meteo.
- The interface follows macOS automatically: English for English systems, Russian for Russian systems.

### Quick start

1. Download `WeatherLoop-…-macOS-universal.zip` from Releases.
2. Unzip the archive and move `WeatherLoop.app` to Applications.
3. Launch the app, choose **Videos for Weather**, and select a local video for each scene.
4. Set a city or allow location access, then choose **Refresh Weather**.

Releases are currently unsigned and not notarized. On first launch, macOS may ask for confirmation; Control-click the app in Finder and choose **Open**.

To build from source, use macOS 14+ with Xcode Command Line Tools:

```sh
git clone <repository-url>
cd WeatherLoop
zsh build.sh
open WeatherLoop.app
```

### How it works

macOS has no public API for turning an arbitrary MP4 into a system dynamic wallpaper. WeatherLoop instead creates a non-interactive video window at desktop level: above the static wallpaper and below icons and normal apps. The effect is reversible, but the app must keep running; on quit, macOS immediately shows the previous static wallpaper.

For weather, WeatherLoop talks directly to [Open-Meteo](https://open-meteo.com/en/docs). A manual lookup sends the city name; Location Services sends coordinates. There is no telemetry or account.

### Releases

Every push and pull request to `main` builds in GitHub Actions. Pushing a version tag creates a universal Apple Silicon + Intel ZIP and a GitHub Release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The code is available under the [MIT License](LICENSE). It applies to WeatherLoop only; users are responsible for having the rights to the videos they choose.
