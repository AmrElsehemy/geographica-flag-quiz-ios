import Foundation
import GameTimePersistence

/// What the UserDefaults stores share: GameTimeKit's `SaveStore` under each store's existing key and
/// JSON format, so a save that cannot be read is backed up instead of being replaced by fresh progress
/// on the next save.
final class DefaultsSave<Value: Codable>: @unchecked Sendable {
    private let store: SaveStore<Value>
    private let lock = NSLock()
    private var recovery: SaveRecovery?

    init(defaults: UserDefaults, key: String, makeDefault: @escaping @Sendable () -> Value) {
        store = SaveStore(key: key, codec: .json, defaults: defaults, makeDefault: makeDefault)
    }

    func load() -> Value {
        let result = store.load()
        let recovery: SaveRecovery? = if case let .recovered(_, recovery) = result { recovery } else { nil }
        lock.withLock { self.recovery = recovery }
        return result.value
    }

    func save(_ value: Value) {
        store.save(value)
    }

    /// Set when the most recent load found a save it could not read (and backed it up); nil otherwise.
    var lastRecovery: SaveRecovery? { lock.withLock { recovery } }
}

/// A store that can say whether its last load had to back up an unreadable save.
public protocol RecoveryReporting {
    var lastRecovery: SaveRecovery? { get }
}
