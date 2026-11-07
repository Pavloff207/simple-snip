import Foundation

/// The outline the user draws when snipping.
enum SnipMode: String {
    case freeform
    case rectangle
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let snipShortcut = "snipShortcut"
        static let snipMode = "snipMode"
        static let autoCopyChanges = "autoCopyChanges"
        static let askToSaveEdits = "askToSaveEdits"
        static let penStyle = "penStyle"
        static let highlighterStyle = "highlighterStyle"
    }

    private let defaults = UserDefaults.standard

    @Published var snipShortcut: Shortcut {
        didSet {
            store(snipShortcut, forKey: Key.snipShortcut)
            registerHotKey()
        }
    }

    /// False when macOS or another app already owns the chosen shortcut.
    @Published private(set) var snipShortcutIsAvailable = true

    @Published var snipMode: SnipMode {
        didSet { defaults.set(snipMode.rawValue, forKey: Key.snipMode) }
    }

    /// Copies the screenshot to the clipboard again after every edit.
    @Published var autoCopyChanges: Bool {
        didSet { defaults.set(autoCopyChanges, forKey: Key.autoCopyChanges) }
    }

    /// Asks before closing an editor window whose edits haven't been saved.
    @Published var askToSaveEdits: Bool {
        didSet { defaults.set(askToSaveEdits, forKey: Key.askToSaveEdits) }
    }

    @Published var penStyle: InkStyle {
        didSet { store(penStyle, forKey: Key.penStyle) }
    }

    @Published var highlighterStyle: InkStyle {
        didSet { store(highlighterStyle, forKey: Key.highlighterStyle) }
    }

    private init() {
        defaults.register(defaults: [
            Key.autoCopyChanges: true,
            Key.askToSaveEdits: true,
        ])
        snipShortcut = Self.load(Shortcut.self, forKey: Key.snipShortcut) ?? .defaultSnip
        snipMode = defaults.string(forKey: Key.snipMode).flatMap(SnipMode.init) ?? .freeform
        autoCopyChanges = defaults.bool(forKey: Key.autoCopyChanges)
        askToSaveEdits = defaults.bool(forKey: Key.askToSaveEdits)
        penStyle = Self.load(InkStyle.self, forKey: Key.penStyle) ?? .defaultPen
        highlighterStyle = Self.load(InkStyle.self, forKey: Key.highlighterStyle) ?? .defaultHighlighter
    }

    func registerHotKey() {
        snipShortcutIsAvailable = HotKeyCenter.shared.register(snipShortcut)
    }

    func style(for kind: InkKind) -> InkStyle {
        kind == .pen ? penStyle : highlighterStyle
    }

    private func store<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
