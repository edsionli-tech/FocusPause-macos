import Foundation

struct LocalStorageSnapshot {
    var todos: [TodoItem]?
    var settings: FocusPauseSettings?
}

struct LocalStorageService {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let todosKey = "focuspause.todos"
    private let settingsKey = "focuspause.settings"

    func load() -> LocalStorageSnapshot {
        let defaults = UserDefaults.standard
        let todos = defaults.data(forKey: todosKey).flatMap { try? decoder.decode([TodoItem].self, from: $0) }
        let settings = defaults.data(forKey: settingsKey).flatMap { try? decoder.decode(FocusPauseSettings.self, from: $0) }
        return LocalStorageSnapshot(todos: todos, settings: settings)
    }

    func save(todos: [TodoItem], settings: FocusPauseSettings) {
        let defaults = UserDefaults.standard
        defaults.set(try? encoder.encode(todos), forKey: todosKey)
        defaults.set(try? encoder.encode(settings), forKey: settingsKey)
    }
}
