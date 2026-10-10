import Foundation

/// Reading progress saved in `UserDefaults` without ever losing it.
enum SavedData {
    /// The value saved under `key`, or nil if there is none or it can't be read. Data that can't be read
    /// (a format from another build) is first copied to `<key>.unreadable`, once, so starting fresh and
    /// saving over `key` never destroys it; a later build can still recover it from there.
    static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        if let value = try? JSONDecoder().decode(type, from: data) { return value }
        let backupKey = key + ".unreadable"
        if defaults.data(forKey: backupKey) == nil {
            defaults.set(data, forKey: backupKey)
        }
        return nil
    }
}
