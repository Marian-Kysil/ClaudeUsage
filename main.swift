// ClaudeUsage — мінімальний віджет лімітів Claude для рядка меню macOS.
//
// Що робить:
//   • раз на 5 хвилин читає токен входу Claude Code
//     (з Keychain, запис "Claude Code-credentials", або з ~/.claude/.credentials.json);
//   • робить ОДИН запит на https://api.anthropic.com/api/oauth/usage — і більше нікуди;
//   • показує 5-годинний і тижневий ліміти в рядку меню.
//
// Чого НЕ робить:
//   • не зберігає токен, не пише його в жодні файли, не логує;
//   • не оновлює токен (щоб не зламати вхід самого Claude Code);
//   • не надсилає запитів до моделі — ліміти не витрачаються.

import Cocoa
import Security
import ServiceManagement
import UserNotifications

// MARK: - Дані

struct Limit: Sendable {
    let key: String
    let title: String
    let percent: Double
    let resetsAt: Date?
}

enum FetchError: Error, Equatable, Sendable {
    case noCredentials
    case keychainDenied
    case tokenExpired
    case rateLimited
    case http(Int)
    case parse
    case network(String)

    func message(_ s: Strings) -> String {
        switch self {
        case .noCredentials:  return s.noCredentials
        case .keychainDenied: return s.keychainDenied
        case .tokenExpired:   return s.tokenExpired
        case .rateLimited:    return s.rateLimited
        case .http(let c):    return "\(s.serverError) (\(c))."
        case .parse:          return s.parseError
        case .network(let e): return "\(s.noConnection) \(e)"
        }
    }
}

// MARK: - Мови інтерфейсу

enum Language: String, CaseIterable {
    case en, uk, de, fr, es, it, pl

    /// Назва мови її ж мовою — для меню вибору.
    var nativeName: String {
        switch self {
        case .en: return "English"
        case .uk: return "Українська"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .it: return "Italiano"
        case .pl: return "Polski"
        }
    }

    private static let defaultsKey = "language"

    /// Збережений вибір; якщо його немає — мова системи, а якщо вона не підтримується — англійська.
    static var current: Language {
        get {
            if let raw = UserDefaults.standard.string(forKey: defaultsKey),
               let l = Language(rawValue: raw) { return l }
            for id in Locale.preferredLanguages {
                if let code = Locale(identifier: id).language.languageCode?.identifier,
                   let l = Language(rawValue: code) { return l }
            }
            return .en
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var strings: Strings {
        switch self {
        case .en: return .en
        case .uk: return .uk
        case .de: return .de
        case .fr: return .fr
        case .es: return .es
        case .it: return .it
        case .pl: return .pl
        }
    }
}

struct Strings: Sendable {
    let noCredentials, keychainDenied, tokenExpired, rateLimited: String
    let serverError, parseError, noConnection: String
    let session5h, week, weekOpus, weekSonnet: String
    let short5h, short7d: String
    let loading, resetsIn, updatedAt, refreshNow, quit, language: String
    let settings, notifyAt90, launchAtLogin, almostReached: String
    let colors, gradientMode, singleMode, colorAt, showBackground, backgroundColor, resetColors: String
    let day, hour, minute: String

    /// Назва ліміту за ключем з відповіді API; nil — якщо ключ невідомий.
    func limitTitle(_ key: String) -> String? {
        switch key {
        case "five_hour":        return session5h
        case "seven_day":        return week
        case "seven_day_opus":   return weekOpus
        case "seven_day_sonnet": return weekSonnet
        default:                 return nil
        }
    }

    static let en = Strings(
        noCredentials: "Claude Code sign-in not found. Run claude and use /login.",
        keychainDenied: "Keychain access denied. Relaunch and click “Always Allow”.",
        tokenExpired: "Token expired. Open Claude Code and do anything there.",
        rateLimited: "Too many requests — will retry later.",
        serverError: "Server error",
        parseError: "Couldn't parse the response (the format may have changed).",
        noConnection: "No connection:",
        session5h: "Session (5 h)", week: "Week",
        weekOpus: "Week · Opus", weekSonnet: "Week · Sonnet",
        short5h: "5h", short7d: "7d",
        loading: "Loading…", resetsIn: "resets in", updatedAt: "Updated at",
        refreshNow: "Refresh Now", quit: "Quit", language: "Language",
        settings: "Settings", notifyAt90: "Notify at 90%", launchAtLogin: "Open at Login",
        almostReached: "Claude limit almost reached",
        colors: "Colors", gradientMode: "Color by Usage", singleMode: "Single Color", colorAt: "Color at",
        showBackground: "Show Background", backgroundColor: "Background Color…", resetColors: "Reset Colors",
        day: "d", hour: "h", minute: "min")

    static let uk = Strings(
        noCredentials: "Не знайдено вхід Claude Code. Запустіть claude і виконайте /login.",
        keychainDenied: "Доступ до Keychain заборонено. Перезапустіть і натисніть «Завжди дозволяти».",
        tokenExpired: "Токен застарів. Відкрийте Claude Code і виконайте будь-яку дію.",
        rateLimited: "Забагато запитів — спробую пізніше.",
        serverError: "Помилка сервера",
        parseError: "Не вдалося розібрати відповідь (можливо, змінився формат).",
        noConnection: "Немає з'єднання:",
        session5h: "Сесія (5 год)", week: "Тиждень",
        weekOpus: "Тиждень · Opus", weekSonnet: "Тиждень · Sonnet",
        short5h: "5г", short7d: "7д",
        loading: "Завантаження…", resetsIn: "скидання через", updatedAt: "Оновлено о",
        refreshNow: "Оновити зараз", quit: "Вийти", language: "Мова",
        settings: "Налаштування", notifyAt90: "Сповіщати при 90%", launchAtLogin: "Запускати разом із системою",
        almostReached: "Ліміт Claude майже вичерпано",
        colors: "Кольори", gradientMode: "Колір за відсотком", singleMode: "Один колір", colorAt: "Колір для",
        showBackground: "Показувати фон", backgroundColor: "Колір фону…", resetColors: "Скинути кольори",
        day: "д", hour: "год", minute: "хв")

    static let de = Strings(
        noCredentials: "Keine Claude-Code-Anmeldung gefunden. Starten Sie claude und führen Sie /login aus.",
        keychainDenied: "Zugriff auf den Schlüsselbund verweigert. Neu starten und „Immer erlauben“ klicken.",
        tokenExpired: "Token abgelaufen. Öffnen Sie Claude Code und führen Sie eine beliebige Aktion aus.",
        rateLimited: "Zu viele Anfragen – neuer Versuch später.",
        serverError: "Serverfehler",
        parseError: "Antwort konnte nicht gelesen werden (Format evtl. geändert).",
        noConnection: "Keine Verbindung:",
        session5h: "Sitzung (5 Std.)", week: "Woche",
        weekOpus: "Woche · Opus", weekSonnet: "Woche · Sonnet",
        short5h: "5h", short7d: "7T",
        loading: "Wird geladen…", resetsIn: "Reset in", updatedAt: "Aktualisiert um",
        refreshNow: "Jetzt aktualisieren", quit: "Beenden", language: "Sprache",
        settings: "Einstellungen", notifyAt90: "Bei 90 % benachrichtigen", launchAtLogin: "Beim Anmelden öffnen",
        almostReached: "Claude-Limit fast erreicht",
        colors: "Farben", gradientMode: "Farbe nach Auslastung", singleMode: "Einheitliche Farbe", colorAt: "Farbe bei",
        showBackground: "Hintergrund anzeigen", backgroundColor: "Hintergrundfarbe…", resetColors: "Farben zurücksetzen",
        day: "T", hour: "Std.", minute: "Min.")

    static let fr = Strings(
        noCredentials: "Connexion Claude Code introuvable. Lancez claude et exécutez /login.",
        keychainDenied: "Accès au trousseau refusé. Relancez et cliquez sur « Toujours autoriser ».",
        tokenExpired: "Jeton expiré. Ouvrez Claude Code et effectuez n’importe quelle action.",
        rateLimited: "Trop de requêtes — nouvel essai plus tard.",
        serverError: "Erreur du serveur",
        parseError: "Impossible d’analyser la réponse (le format a peut-être changé).",
        noConnection: "Pas de connexion :",
        session5h: "Session (5 h)", week: "Semaine",
        weekOpus: "Semaine · Opus", weekSonnet: "Semaine · Sonnet",
        short5h: "5h", short7d: "7j",
        loading: "Chargement…", resetsIn: "réinitialisation dans", updatedAt: "Mis à jour à",
        refreshNow: "Actualiser", quit: "Quitter", language: "Langue",
        settings: "Réglages", notifyAt90: "Notifier à 90 %", launchAtLogin: "Ouvrir à la connexion",
        almostReached: "Limite Claude presque atteinte",
        colors: "Couleurs", gradientMode: "Couleur selon l’utilisation", singleMode: "Couleur unique", colorAt: "Couleur à",
        showBackground: "Afficher le fond", backgroundColor: "Couleur du fond…", resetColors: "Réinitialiser les couleurs",
        day: "j", hour: "h", minute: "min")

    static let es = Strings(
        noCredentials: "No se encontró el inicio de sesión de Claude Code. Ejecuta claude y usa /login.",
        keychainDenied: "Acceso al llavero denegado. Reinicia y pulsa «Permitir siempre».",
        tokenExpired: "Token caducado. Abre Claude Code y realiza cualquier acción.",
        rateLimited: "Demasiadas solicitudes: lo intentaré más tarde.",
        serverError: "Error del servidor",
        parseError: "No se pudo interpretar la respuesta (puede que haya cambiado el formato).",
        noConnection: "Sin conexión:",
        session5h: "Sesión (5 h)", week: "Semana",
        weekOpus: "Semana · Opus", weekSonnet: "Semana · Sonnet",
        short5h: "5h", short7d: "7d",
        loading: "Cargando…", resetsIn: "se restablece en", updatedAt: "Actualizado a las",
        refreshNow: "Actualizar ahora", quit: "Salir", language: "Idioma",
        settings: "Ajustes", notifyAt90: "Avisar al 90 %", launchAtLogin: "Abrir al iniciar sesión",
        almostReached: "Límite de Claude casi alcanzado",
        colors: "Colores", gradientMode: "Color según el uso", singleMode: "Color único", colorAt: "Color al",
        showBackground: "Mostrar fondo", backgroundColor: "Color de fondo…", resetColors: "Restablecer colores",
        day: "d", hour: "h", minute: "min")

    static let it = Strings(
        noCredentials: "Accesso a Claude Code non trovato. Avvia claude ed esegui /login.",
        keychainDenied: "Accesso al portachiavi negato. Riavvia e fai clic su «Consenti sempre».",
        tokenExpired: "Token scaduto. Apri Claude Code ed esegui un’azione qualsiasi.",
        rateLimited: "Troppe richieste: riproverò più tardi.",
        serverError: "Errore del server",
        parseError: "Impossibile interpretare la risposta (il formato potrebbe essere cambiato).",
        noConnection: "Nessuna connessione:",
        session5h: "Sessione (5 h)", week: "Settimana",
        weekOpus: "Settimana · Opus", weekSonnet: "Settimana · Sonnet",
        short5h: "5h", short7d: "7g",
        loading: "Caricamento…", resetsIn: "reset tra", updatedAt: "Aggiornato alle",
        refreshNow: "Aggiorna ora", quit: "Esci", language: "Lingua",
        settings: "Impostazioni", notifyAt90: "Avvisa al 90%", launchAtLogin: "Apri al login",
        almostReached: "Limite di Claude quasi raggiunto",
        colors: "Colori", gradientMode: "Colore in base all’uso", singleMode: "Colore unico", colorAt: "Colore al",
        showBackground: "Mostra sfondo", backgroundColor: "Colore di sfondo…", resetColors: "Ripristina colori",
        day: "g", hour: "h", minute: "min")

    static let pl = Strings(
        noCredentials: "Nie znaleziono logowania Claude Code. Uruchom claude i wykonaj /login.",
        keychainDenied: "Odmowa dostępu do pęku kluczy. Uruchom ponownie i kliknij „Zawsze pozwalaj”.",
        tokenExpired: "Token wygasł. Otwórz Claude Code i wykonaj dowolną czynność.",
        rateLimited: "Zbyt wiele żądań — spróbuję później.",
        serverError: "Błąd serwera",
        parseError: "Nie udało się odczytać odpowiedzi (format mógł się zmienić).",
        noConnection: "Brak połączenia:",
        session5h: "Sesja (5 godz.)", week: "Tydzień",
        weekOpus: "Tydzień · Opus", weekSonnet: "Tydzień · Sonnet",
        short5h: "5h", short7d: "7d",
        loading: "Ładowanie…", resetsIn: "reset za", updatedAt: "Zaktualizowano o",
        refreshNow: "Odśwież teraz", quit: "Zakończ", language: "Język",
        settings: "Ustawienia", notifyAt90: "Powiadamiaj przy 90%", launchAtLogin: "Uruchamiaj przy logowaniu",
        almostReached: "Limit Claude prawie wyczerpany",
        colors: "Kolory", gradientMode: "Kolor wg zużycia", singleMode: "Jeden kolor", colorAt: "Kolor przy",
        showBackground: "Pokaż tło", backgroundColor: "Kolor tła…", resetColors: "Przywróć kolory",
        day: "d", hour: "godz.", minute: "min")
}

// MARK: - Отримання даних

enum UsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static let titles: [String: String] = [
        "five_hour": "Сесія (5 год)",
        "seven_day": "Тиждень",
        "seven_day_opus": "Тиждень · Opus",
        "seven_day_sonnet": "Тиждень · Sonnet",
    ]

    /// Читає JSON з обліковими даними Claude Code: спершу Keychain, потім файл.
    static func credentialsJSON() throws -> [String: Any] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        if status == errSecUserCanceled || status == errSecAuthFailed {
            throw FetchError.keychainDenied
        }
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        throw FetchError.noCredentials
    }

    static func accessToken() throws -> String {
        let json = try credentialsJSON()
        guard let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw FetchError.noCredentials
        }
        if let exp = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: exp / 1000) < Date() {
            throw FetchError.tokenExpired
        }
        return token
    }

    static func fetch() async throws -> [Limit] {
        let token = try accessToken()

        var req = URLRequest(url: endpoint,
                             cachePolicy: .reloadIgnoringLocalCacheData,
                             timeoutInterval: 20)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw FetchError.network(error.localizedDescription)
        }

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401: throw FetchError.tokenExpired
        case 429: throw FetchError.rateLimited
        case let code: throw FetchError.http(code)
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError.parse
        }
        let limits = parse(obj)
        if limits.isEmpty { throw FetchError.parse }
        return limits
    }

    static func parse(_ obj: [String: Any]) -> [Limit] {
        var out: [Limit] = []
        for (key, value) in obj {
            guard let d = value as? [String: Any],
                  let u = (d["utilization"] as? NSNumber)?.doubleValue else { continue }
            let reset = (d["resets_at"] as? String).flatMap(parseDate)
            let title = titles[key] ?? key.replacingOccurrences(of: "_", with: " ")
            out.append(Limit(key: key, title: title, percent: u, resetsAt: reset))
        }
        let order = ["five_hour", "seven_day"]
        return out.sorted { a, b in
            let ia = order.firstIndex(of: a.key) ?? 99
            let ib = order.firstIndex(of: b.key) ?? 99
            return ia != ib ? ia < ib : a.key < b.key
        }
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return f.date(from: trimmed)
    }
}

// MARK: - Колір за відсотком

enum UsageColor {
    /// Відсотки опорних точок шкали; їхні кольори задаються в налаштуваннях.
    static let positions: [Double] = [0, 25, 50, 75, 100]

    /// Колір для відсотка: або єдиний, або плавний перехід між сусідніми опорними точками.
    static func color(for percent: Double) -> NSColor {
        if Prefs.singleColorMode { return Prefs.singleColor }
        let colors = Prefs.stopColors.map { $0.usingColorSpace(.sRGB) ?? $0 }
        let p = min(max(percent, 0), 100)
        var i = 0
        while i < positions.count - 2 && p > positions[i + 1] { i += 1 }
        let t = CGFloat((p - positions[i]) / (positions[i + 1] - positions[i]))
        let a = colors[i], b = colors[i + 1]
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        return NSColor(srgbRed: mix(a.redComponent, b.redComponent),
                       green: mix(a.greenComponent, b.greenComponent),
                       blue: mix(a.blueComponent, b.blueComponent), alpha: 1)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    /// Чи темний колір — щоб підібрати світлий або темний текст поверх нього.
    var isDark: Bool {
        let c = usingColorSpace(.sRGB) ?? self
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent < 0.5
    }
}

// MARK: - Налаштування

enum Prefs {
    static var notifyAt90: Bool {
        get { UserDefaults.standard.object(forKey: "notifyAt90") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifyAt90") }
    }

    /// Ліміти, про які вже сповіщено; ключ зникає, коли ліміт знову нижче 90 %.
    static var notifiedKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "notified90") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "notified90") }
    }

    // Кольори

    static let defaultStops = ["#2E7D32", "#8BC34A", "#FDD835", "#FB8C00", "#D32F2F"]
    static let defaultSingle = "#F3F4F6"
    static let defaultBackground = "#111827"
    private static let colorKeys = ["stopColors", "singleColorMode", "singleColor",
                                    "showBackground", "backgroundColor"]

    static var stopColors: [NSColor] {
        get {
            let hexes = UserDefaults.standard.stringArray(forKey: "stopColors") ?? defaultStops
            let colors = hexes.compactMap { NSColor(hex: $0) }
            return colors.count == defaultStops.count ? colors : defaultStops.compactMap { NSColor(hex: $0) }
        }
        set { UserDefaults.standard.set(newValue.map(\.hexString), forKey: "stopColors") }
    }

    static var singleColorMode: Bool {
        get { UserDefaults.standard.bool(forKey: "singleColorMode") }
        set { UserDefaults.standard.set(newValue, forKey: "singleColorMode") }
    }

    static var singleColor: NSColor {
        get { color("singleColor", defaultSingle) }
        set { UserDefaults.standard.set(newValue.hexString, forKey: "singleColor") }
    }

    static var showBackground: Bool {
        get { UserDefaults.standard.object(forKey: "showBackground") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showBackground") }
    }

    static var backgroundColor: NSColor {
        get { color("backgroundColor", defaultBackground) }
        set { UserDefaults.standard.set(newValue.hexString, forKey: "backgroundColor") }
    }

    static func resetColors() {
        colorKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private static func color(_ key: String, _ fallback: String) -> NSColor {
        UserDefaults.standard.string(forKey: key).flatMap { NSColor(hex: $0) } ?? NSColor(hex: fallback)!
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("ClaudeUsage: login item: \(error.localizedDescription)")
        }
    }

    /// Вмикає автозапуск лише під час першого запуску — далі рішення за користувачем.
    static func setUpOnFirstLaunch() {
        let key = "loginItemConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(true)
    }
}

// MARK: - Рядок меню

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var limits: [Limit] = []
    private var lastError: FetchError?
    private var lastUpdate: Date?
    private var timer: Timer?
    private var interval: TimeInterval = 300   // 5 хвилин
    private var isFetching = false

    private let barFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    private var s: Strings { Language.current.strings }

    /// Який колір зараз редагується в палітрі: 0…4 — опорні точки, 10 — єдиний колір, 20 — фон.
    private var editingColorTag: Int?
    private static let singleColorTag = 10, backgroundTag = 20

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        setTitle("✳︎ …")
        UNUserNotificationCenter.current().delegate = self
        if Prefs.notifyAt90 { requestNotificationPermission() }
        LoginItem.setUpOnFirstLaunch()
        refresh()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func didWake() {
        perform(#selector(refresh), with: nil, afterDelay: 10)
    }

    @objc private func refresh() {
        guard !isFetching else { return }
        isFetching = true
        Task {
            do {
                // Лише відомі ліміти: сервер може повертати й внутрішні, без зрозумілої назви.
                limits = try await UsageClient.fetch().filter { Strings.en.limitTitle($0.key) != nil }
                lastError = nil
                lastUpdate = Date()
                interval = 300
                checkThresholds()
            } catch let e as FetchError {
                lastError = e
                interval = (e == .rateLimited) ? min(interval * 2, 3600) : 300
            } catch {
                lastError = .network(error.localizedDescription)
                interval = 300
            }
            isFetching = false
            updateTitle()
            scheduleNext()
        }
    }

    // MARK: Сповіщення

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Одне сповіщення на ліміт, коли він перетинає 90 %; повторно — лише після того, як ліміт скинеться.
    private func checkThresholds() {
        var sent = Prefs.notifiedKeys
        for l in limits {
            if l.percent >= 90 {
                if !sent.contains(l.key) {
                    sent.insert(l.key)
                    if Prefs.notifyAt90 { notify(l) }
                }
            } else {
                sent.remove(l.key)
            }
        }
        Prefs.notifiedKeys = sent
    }

    private func notify(_ l: Limit) {
        let c = UNMutableNotificationContent()
        c.title = s.almostReached
        var body = "\(s.limitTitle(l.key) ?? l.title) — \(Int(l.percent.rounded()))%"
        if let r = l.resetsAt { body += " · \(s.resetsIn) " + countdown(to: r) }
        c.body = body
        c.sound = .default
        let req = UNNotificationRequest(identifier: "limit-\(l.key)", content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Показувати банер, навіть коли меню застосунку відкрите.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    private func scheduleNext() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, target: self,
                      selector: #selector(refresh), userInfo: nil, repeats: false)
        t.tolerance = 60   // дозволяє системі групувати пробудження — економія батареї
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Заголовок у рядку меню

    private func setTitle(_ text: String) {
        render(NSAttributedString(string: text, attributes: [.font: barFont, .foregroundColor: barTextColor]))
    }

    /// Колір підписів: на фоні — контрастний до нього, без фону — системний.
    private var barTextColor: NSColor {
        guard Prefs.showBackground else { return .labelColor }
        return Prefs.backgroundColor.isDark ? .white : .black
    }

    private var barSecondaryColor: NSColor {
        guard Prefs.showBackground else { return .secondaryLabelColor }
        return barTextColor.withAlphaComponent(0.55)
    }

    /// Показує текст у рядку меню — або як є, або на заокругленій «пігулці» кольору фону.
    private func render(_ str: NSAttributedString) {
        guard let button = statusItem.button else { return }
        guard Prefs.showBackground else {
            button.image = nil
            button.attributedTitle = str
            return
        }
        let padX: CGFloat = 7, height: CGFloat = 18
        let textSize = str.size()
        let size = NSSize(width: ceil(textSize.width) + padX * 2, height: height)
        let bg = Prefs.backgroundColor
        let image = NSImage(size: size, flipped: false) { rect in
            bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            str.draw(at: NSPoint(x: padX, y: (height - textSize.height) / 2))
            return true
        }
        image.isTemplate = false
        button.attributedTitle = NSAttributedString(string: "")
        button.image = image
        button.imagePosition = .imageOnly
    }

    private func updateTitle() {
        let short = ["five_hour": s.short5h, "seven_day": s.short7d]
        var shown = limits.filter { short[$0.key] != nil }
        if shown.isEmpty { shown = Array(limits.prefix(1)) }
        guard !shown.isEmpty else {
            setTitle(lastError == nil ? "✳︎ …" : "✳︎ ⚠︎")
            return
        }
        let str = NSMutableAttributedString()
        for (i, l) in shown.enumerated() {
            if i > 0 {
                str.append(NSAttributedString(string: " · ", attributes: [
                    .font: barFont, .foregroundColor: barSecondaryColor]))
            }
            if let label = short[l.key] {
                str.append(NSAttributedString(string: "\(label) ", attributes: [
                    .font: barFont, .foregroundColor: barTextColor]))
            }
            str.append(NSAttributedString(string: "\(Int(l.percent.rounded()))%", attributes: [
                .font: barFont, .foregroundColor: UsageColor.color(for: l.percent)]))
        }
        if lastError != nil {
            str.append(NSAttributedString(string: " ⚠︎", attributes: [
                .font: barFont, .foregroundColor: NSColor.systemOrange]))
        }
        render(str)
    }

    // MARK: Випадне меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let e = lastError {
            menu.addItem(info("⚠︎ " + e.message(s)))
            menu.addItem(.separator())
        }
        if limits.isEmpty && lastError == nil {
            menu.addItem(info(s.loading))
        }
        for l in limits {
            menu.addItem(limitHeader(s.limitTitle(l.key) ?? l.title, l.percent))
            menu.addItem(barItem(l.percent, resetsAt: l.resetsAt))
        }
        if let u = lastUpdate {
            menu.addItem(.separator())
            let f = DateFormatter()
            f.locale = Locale(identifier: Language.current.rawValue)
            f.dateStyle = .none
            f.timeStyle = .short
            menu.addItem(info("\(s.updatedAt) " + f.string(from: u), secondary: true))
        }
        menu.addItem(.separator())
        menu.addItem(action(s.refreshNow, #selector(refresh), key: "r"))
        menu.addItem(settingsMenu())
        menu.addItem(action(s.quit, #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func settingsMenu() -> NSMenuItem {
        let item = NSMenuItem(title: s.settings, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(languageMenu())
        sub.addItem(colorsMenu())
        sub.addItem(.separator())
        let notifyItem = action(s.notifyAt90, #selector(toggleNotify), key: "")
        notifyItem.state = Prefs.notifyAt90 ? .on : .off
        sub.addItem(notifyItem)
        let loginItem = action(s.launchAtLogin, #selector(toggleLaunchAtLogin), key: "")
        loginItem.state = LoginItem.isEnabled ? .on : .off
        sub.addItem(loginItem)
        item.submenu = sub
        return item
    }

    private func colorsMenu() -> NSMenuItem {
        let item = NSMenuItem(title: s.colors, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        let single = Prefs.singleColorMode

        let gradient = action(s.gradientMode, #selector(setColorMode(_:)), key: "")
        gradient.tag = 0
        gradient.state = single ? .off : .on
        sub.addItem(gradient)
        let one = action(s.singleMode, #selector(setColorMode(_:)), key: "")
        one.tag = 1
        one.state = single ? .on : .off
        sub.addItem(one)
        sub.addItem(.separator())

        for (i, c) in Prefs.stopColors.enumerated() {
            let pos = Int(UsageColor.positions[i])
            sub.addItem(colorItem("\(s.colorAt) \(pos)%…", c, tag: i, enabled: !single))
        }
        sub.addItem(colorItem("\(s.singleMode)…", Prefs.singleColor, tag: Self.singleColorTag, enabled: single))
        sub.addItem(.separator())

        let bgToggle = action(s.showBackground, #selector(toggleBackground), key: "")
        bgToggle.state = Prefs.showBackground ? .on : .off
        sub.addItem(bgToggle)
        sub.addItem(colorItem(s.backgroundColor, Prefs.backgroundColor, tag: Self.backgroundTag,
                              enabled: Prefs.showBackground))
        sub.addItem(.separator())
        sub.addItem(action(s.resetColors, #selector(resetColors), key: ""))

        item.submenu = sub
        return item
    }

    private func colorItem(_ title: String, _ color: NSColor, tag: Int, enabled: Bool) -> NSMenuItem {
        let item = action(title, #selector(pickColor(_:)), key: "")
        item.tag = tag
        item.isEnabled = enabled
        item.image = swatch(color)
        return item
    }

    /// Невеликий заокруглений квадратик кольору для пункту меню.
    private func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            color.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            return true
        }
    }

    @objc private func setColorMode(_ sender: NSMenuItem) {
        Prefs.singleColorMode = sender.tag == 1
        updateTitle()
    }

    @objc private func toggleBackground() {
        Prefs.showBackground.toggle()
        updateTitle()
    }

    @objc private func resetColors() {
        Prefs.resetColors()
        updateTitle()
    }

    @objc private func pickColor(_ sender: NSMenuItem) {
        editingColorTag = sender.tag
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(nil)
        panel.color = currentColor(tag: sender.tag)
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        guard let tag = editingColorTag else { return }
        let c = sender.color
        switch tag {
        case Self.singleColorTag: Prefs.singleColor = c
        case Self.backgroundTag:  Prefs.backgroundColor = c
        default:
            var stops = Prefs.stopColors
            stops[tag] = c
            Prefs.stopColors = stops
        }
        updateTitle()
    }

    private func currentColor(tag: Int) -> NSColor {
        switch tag {
        case Self.singleColorTag: return Prefs.singleColor
        case Self.backgroundTag:  return Prefs.backgroundColor
        default:                  return Prefs.stopColors[tag]
        }
    }

    @objc private func toggleNotify() {
        Prefs.notifyAt90.toggle()
        if Prefs.notifyAt90 { requestNotificationPermission() }
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.set(!LoginItem.isEnabled)
    }

    private func languageMenu() -> NSMenuItem {
        let item = NSMenuItem(title: s.language, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for lang in Language.allCases {
            let li = NSMenuItem(title: lang.nativeName, action: #selector(setLanguage(_:)), keyEquivalent: "")
            li.target = self
            li.representedObject = lang.rawValue
            li.state = lang == Language.current ? .on : .off
            sub.addItem(li)
        }
        item.submenu = sub
        return item
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = Language(rawValue: raw) else { return }
        Language.current = lang
        updateTitle()
    }

    private func info(_ text: String, bold: Bool = false, mono: Bool = false,
                      secondary: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        let font: NSFont = mono ? .monospacedSystemFont(ofSize: 12, weight: .regular)
                         : (bold ? .boldSystemFont(ofSize: 13) : .menuFont(ofSize: 13))
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: secondary ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
        return item
    }

    private func action(_ title: String, _ sel: Selector, key: String,
                        target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    /// «Назва — 42%», де кольорові лише цифри й знак відсотка.
    private func limitHeader(_ title: String, _ p: Double) -> NSMenuItem {
        let font = NSFont.boldSystemFont(ofSize: 13)
        let str = NSMutableAttributedString(string: "\(title) — ", attributes: [
            .font: font, .foregroundColor: NSColor.labelColor])
        str.append(NSAttributedString(string: "\(Int(p.rounded()))%", attributes: [
            .font: font, .foregroundColor: UsageColor.color(for: p)]))
        let item = NSMenuItem(title: str.string, action: nil, keyEquivalent: "")
        item.attributedTitle = str
        return item
    }

    /// Шкала з 20 поділок: кожна заповнена поділка має колір свого відсотка, тож шкала переливається.
    private func barItem(_ p: Double, resetsAt: Date?) -> NSMenuItem {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let n = Int((min(max(p, 0), 100) / 5).rounded())
        let str = NSMutableAttributedString()
        for i in 0..<20 {
            let filled = i < n
            str.append(NSAttributedString(string: filled ? "█" : "░", attributes: [
                .font: font,
                .foregroundColor: filled ? UsageColor.color(for: Double(i) * 5 + 2.5) : NSColor.tertiaryLabelColor,
            ]))
        }
        if let r = resetsAt {
            str.append(NSAttributedString(string: "   \(s.resetsIn) " + countdown(to: r), attributes: [
                .font: font, .foregroundColor: NSColor.labelColor]))
        }
        let item = NSMenuItem(title: str.string, action: nil, keyEquivalent: "")
        item.attributedTitle = str
        return item
    }

    private func countdown(to date: Date) -> String {
        let sec = max(0, Int(date.timeIntervalSinceNow))
        let d = sec / 86400, h = (sec % 86400) / 3600, m = (sec % 3600) / 60
        if d > 0 { return "\(d) \(s.day) \(h) \(s.hour)" }
        if h > 0 { return "\(h) \(s.hour) \(m) \(s.minute)" }
        return "\(m) \(s.minute)"
    }
}

// MARK: - Точка входу

@main
@MainActor
enum ClaudeUsageApp {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)   // без іконки в Dock
        app.delegate = delegate
        app.run()
    }
}
