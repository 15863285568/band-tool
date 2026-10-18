import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let softGlass = "miface.softGlass.enabled"
    }

    @Published var softGlassEnabled: Bool {
        didSet {
            UserDefaults.standard.set(softGlassEnabled, forKey: Keys.softGlass)
        }
    }

    init() {
        if UserDefaults.standard.object(forKey: Keys.softGlass) == nil {
            softGlassEnabled = true
        } else {
            softGlassEnabled = UserDefaults.standard.bool(forKey: Keys.softGlass)
        }
    }
}
