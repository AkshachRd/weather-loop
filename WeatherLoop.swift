import AppKit
import AVFoundation
import CoreLocation
import Foundation

private enum WeatherScene: String, CaseIterable {
    case clear
    case cloudy
    case night
    case rain

    var title: String {
        switch self {
        case .clear: "Ясно"
        case .cloudy: "Облачно / туман / снег"
        case .night: "Ночь"
        case .rain: "Дождь / гроза"
        }
    }

    var settingsKey: String { "videoPath.\(rawValue)" }
}

private struct WeatherResponse: Decodable {
    struct Current: Decodable {
        let weatherCode: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    let current: Current
}

private struct GeocodingResponse: Decodable {
    struct Result: Decodable {
        let name: String
        let country: String?
        let latitude: Double
        let longitude: Double
    }

    let results: [Result]?
}

/// A borderless video window that macOS places above the static desktop picture
/// and beneath desktop icons. This is the usual non-private API approach for
/// video wallpapers, so the app must remain open while the wallpaper is active.
private final class WallpaperWindow: NSWindow {
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private var loopObserver: NSObjectProtocol?
    private(set) var videoURL: URL?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        playerLayer.frame = view.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.player = player
        player.actionAtItemEnd = .none
        view.layer?.addSublayer(playerLayer)
        contentView = view
    }

    deinit {
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func play(_ url: URL) {
        guard videoURL != url else { return }

        let item = AVPlayerItem(url: url)
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.player.seek(to: .zero) { finished in
                if finished { self.player.play() }
            }
        }

        player.replaceCurrentItem(with: item)
        videoURL = url
        player.play()
    }

    func pause() { player.pause() }
    func resume() { player.play() }
    func setSoundEnabled(_ enabled: Bool) { player.isMuted = !enabled }
}

private final class WallpaperController {
    private var windows: [WallpaperWindow] = []
    private(set) var activeScene: WeatherScene?
    private(set) var soundEnabled: Bool

    init() {
        soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? false
        rebuildWindows()
    }

    func videoURL(for scene: WeatherScene) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: scene.settingsKey),
              FileManager.default.fileExists(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    func hasVideo(for scene: WeatherScene) -> Bool {
        videoURL(for: scene) != nil
    }

    func setVideoURL(_ url: URL, for scene: WeatherScene) {
        UserDefaults.standard.set(url.path, forKey: scene.settingsKey)
    }

    @discardableResult
    func apply(scene: WeatherScene) -> Bool {
        guard let url = videoURL(for: scene) else { return false }
        windows.forEach { window in
            window.setFrame(window.screen?.frame ?? window.frame, display: true)
            window.play(url)
            window.setSoundEnabled(soundEnabled)
            window.orderFront(nil)
        }
        activeScene = scene
        return true
    }

    func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map(WallpaperWindow.init(screen:))
        windows.forEach { $0.setSoundEnabled(soundEnabled) }
        if let activeScene { _ = apply(scene: activeScene) }
    }

    func pause() { windows.forEach { $0.pause() } }
    func resume() { windows.forEach { $0.resume() } }

    func toggleSound() -> Bool {
        soundEnabled.toggle()
        UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled")
        windows.forEach { $0.setSoundEnabled(soundEnabled) }
        return soundEnabled
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let locationManager = CLLocationManager()
    private let wallpaper = WallpaperController()
    private var refreshTimer: Timer?

    private var statusMenuItem: NSMenuItem!
    private var soundMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var isPaused = false

    private var latitude: Double?
    private var longitude: Double?
    private var cityName: String?
    private var usesMacLocation = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        restoreLocationPreference()
        configureMenu()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if WeatherScene.allCases.allSatisfy(wallpaper.hasVideo(for:)) {
            refreshWeather()
        } else {
            setStatus("Выберите видео для каждой погодной сцены")
        }

        refreshTimer = Timer.scheduledTimer(
            timeInterval: 30 * 60,
            target: self,
            selector: #selector(refreshWeather),
            userInfo: nil,
            repeats: true
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func configureMenu() {
        let icon = NSImage(systemSymbolName: "cloud.sun", accessibilityDescription: "WeatherLoop")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "WeatherLoop"

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Подготовка…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Обновить погоду", action: #selector(refreshWeather), keyEquivalent: "r")
        menu.addItem(withTitle: "Задать город…", action: #selector(promptForCity), keyEquivalent: "")
        menu.addItem(withTitle: "Использовать геопозицию Mac", action: #selector(useMacLocation), keyEquivalent: "")

        let videoMenu = NSMenu(title: "Видео для погоды")
        for scene in WeatherScene.allCases {
            let item = NSMenuItem(title: "\(scene.title)…", action: #selector(chooseVideo(_:)), keyEquivalent: "")
            item.representedObject = scene.rawValue
            item.target = self
            videoMenu.addItem(item)
        }
        let videoMenuItem = NSMenuItem(title: "Видео для погоды", action: nil, keyEquivalent: "")
        videoMenuItem.submenu = videoMenu
        menu.addItem(videoMenuItem)

        loginMenuItem = NSMenuItem(title: loginMenuTitle, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())
        soundMenuItem = NSMenuItem(title: soundMenuTitle, action: #selector(toggleSound), keyEquivalent: "m")
        pauseMenuItem = NSMenuItem(title: "Пауза", action: #selector(togglePause), keyEquivalent: "p")
        menu.addItem(soundMenuItem)
        menu.addItem(pauseMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти из WeatherLoop", action: #selector(quitApplication), keyEquivalent: "q")

        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func restoreLocationPreference() {
        let defaults = UserDefaults.standard
        usesMacLocation = !defaults.bool(forKey: "usesManualCity")
        if !usesMacLocation {
            latitude = defaults.object(forKey: "latitude") as? Double
            longitude = defaults.object(forKey: "longitude") as? Double
            cityName = defaults.string(forKey: "cityName")
        }
    }

    @objc private func screensDidChange() { wallpaper.rebuildWindows() }

    @objc private func chooseVideo(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let scene = WeatherScene(rawValue: rawValue)
        else { return }

        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Видео для сцены «\(scene.title)»"
        panel.message = "Выберите локальный видеофайл. Он не копируется и не загружается куда-либо."
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        wallpaper.setVideoURL(url, for: scene)
        _ = wallpaper.apply(scene: scene)
        setStatus("Видео для «\(scene.title)» выбрано")
    }

    @objc private func refreshWeather() {
        guard WeatherScene.allCases.allSatisfy(wallpaper.hasVideo(for:)) else {
            setStatus("Выберите видео для всех четырёх сцен")
            return
        }
        if usesMacLocation {
            requestMacLocation()
        } else if let latitude, let longitude {
            fetchWeather(latitude: latitude, longitude: longitude, city: cityName ?? "выбранный город")
        } else {
            setStatus("Задайте город или разрешите геопозицию")
        }
    }

    @objc private func useMacLocation() {
        usesMacLocation = true
        latitude = nil
        longitude = nil
        cityName = nil
        UserDefaults.standard.set(false, forKey: "usesManualCity")
        requestMacLocation()
    }

    @objc private func promptForCity() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Город для погоды"
        alert.informativeText = "Например: Москва, Ханой или Berlin. WeatherLoop запрашивает только название города у Open‑Meteo."
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Отмена")
        let input = NSTextField(string: cityName ?? "")
        input.placeholderString = "Название города"
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let city = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { return }
        resolve(city: city)
    }

    @objc private func toggleSound() {
        let enabled = wallpaper.toggleSound()
        soundMenuItem.title = soundMenuTitle
        setStatus(enabled ? "Звук включён" : "Звук выключен")
    }

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            wallpaper.pause()
            pauseMenuItem.title = "Продолжить"
            setStatus("Воспроизведение на паузе")
        } else {
            wallpaper.resume()
            pauseMenuItem.title = "Пауза"
            setStatus("Воспроизведение продолжается")
        }
    }

    @objc private func quitApplication() { NSApp.terminate(nil) }

    private var soundMenuTitle: String {
        wallpaper.soundEnabled ? "Выключить звук" : "Включить звук"
    }

    private func requestMacLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            setStatus("Включите геопозицию или задайте город вручную")
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            setStatus("Определяю погоду по геопозиции Mac…")
            locationManager.requestLocation()
        case .notDetermined:
            setStatus("Разрешите геопозицию для WeatherLoop")
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            setStatus("Геопозиция запрещена — задайте город вручную")
        @unknown default:
            setStatus("Не удалось получить доступ к геопозиции")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        fetchWeather(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            city: "геопозиция Mac"
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        setStatus("Геопозиция недоступна — задайте город вручную")
    }

    private func resolve(city: String) {
        setStatus("Ищу «\(city)»…")
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "ru"),
            URLQueryItem(name: "format", value: "json")
        ]

        URLSession.shared.dataTask(with: components.url!) { [weak self] data, _, error in
            let result = data.flatMap { try? JSONDecoder().decode(GeocodingResponse.self, from: $0).results?.first }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let result else {
                    self.setStatus(error == nil ? "Город не найден" : "Не удалось связаться с Open‑Meteo")
                    return
                }
                self.usesMacLocation = false
                self.latitude = result.latitude
                self.longitude = result.longitude
                self.cityName = [result.name, result.country].compactMap { $0 }.joined(separator: ", ")
                let defaults = UserDefaults.standard
                defaults.set(true, forKey: "usesManualCity")
                defaults.set(result.latitude, forKey: "latitude")
                defaults.set(result.longitude, forKey: "longitude")
                defaults.set(self.cityName, forKey: "cityName")
                self.fetchWeather(latitude: result.latitude, longitude: result.longitude, city: self.cityName!)
            }
        }.resume()
    }

    private func fetchWeather(latitude: Double, longitude: Double, city: String) {
        setStatus("Обновляю погоду: \(city)…")
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        URLSession.shared.dataTask(with: components.url!) { [weak self] data, _, error in
            let response = data.flatMap { try? JSONDecoder().decode(WeatherResponse.self, from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let response else {
                    self.setStatus(error == nil ? "Open‑Meteo вернул неверный ответ" : "Нет соединения с Open‑Meteo")
                    return
                }
                let scene = self.scene(for: response.current)
                guard self.wallpaper.apply(scene: scene) else {
                    self.setStatus("Для «\(scene.title)» не выбрано видео")
                    return
                }
                self.setStatus("\(city): \(scene.title) · обновление через 30 мин")
            }
        }.resume()
    }

    private func scene(for weather: WeatherResponse.Current) -> WeatherScene {
        if weather.isDay == 0 { return .night }
        switch weather.weatherCode {
        case 0, 1: return .clear
        case 2, 3, 45, 48, 71...86: return .cloudy
        case 51...67, 80...82, 95...99: return .rain
        default: return .cloudy
        }
    }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/io.github.akshachrd.weatherloop.plist")
    }

    private var loginMenuTitle: String {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
            ? "Не запускать при входе в Mac"
            : "Запускать при входе в Mac"
    }

    @objc private func toggleLaunchAtLogin() {
        let fileManager = FileManager.default
        let label = "io.github.akshachrd.weatherloop"
        let uid = getuid()

        if fileManager.fileExists(atPath: launchAgentURL.path) {
            runLaunchctl(arguments: ["bootout", "gui/\(uid)", launchAgentURL.path])
            do {
                try fileManager.removeItem(at: launchAgentURL)
                loginMenuItem.title = loginMenuTitle
                setStatus("Автозапуск отключён")
            } catch {
                setStatus("Не удалось отключить автозапуск")
            }
            return
        }

        guard let executable = Bundle.main.executablePath else {
            setStatus("Не найден исполняемый файл приложения")
            return
        }
        let agent: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        do {
            try fileManager.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
            runLaunchctl(arguments: ["bootstrap", "gui/\(uid)", launchAgentURL.path])
            loginMenuItem.title = loginMenuTitle
            setStatus("Автозапуск включён")
        } catch {
            setStatus("Не удалось включить автозапуск")
        }
    }

    private func runLaunchctl(arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    private func setStatus(_ text: String) {
        statusMenuItem?.title = text
        statusItem.button?.toolTip = text
    }
}

@main
struct WeatherLoopApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
