import Foundation
import Security

public enum SnapNoteKeychainError: Error, Equatable {
    case status(OSStatus)
    case corruptData
}

/// Injectable for tests. Implementations must never record the values supplied to them.
public protocol SnapNoteKeychainBackend: Sendable {
    func exists(service: String, account: String) -> Bool
    func read(service: String, account: String) throws -> Data?
    func write(service: String, account: String, value: Data) throws
    func delete(service: String, account: String) throws
}

public extension SnapNoteKeychainBackend {
    func exists(service: String, account: String) -> Bool {
        ((try? read(service: service, account: account)) ?? nil) != nil
    }
}

public struct SnapNoteSystemKeychain: SnapNoteKeychainBackend {
    public init() {}
    private func query(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }
    public func exists(service: String, account: String) -> Bool {
        var q = query(service, account)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
    public func read(service: String, account: String) throws -> Data? {
        var q = query(service, account)
        q[kSecReturnData as String] = kCFBooleanTrue
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SnapNoteKeychainError.status(status) }
        guard let data = result as? Data else { throw SnapNoteKeychainError.corruptData }
        return data
    }
    public func write(service: String, account: String, value: Data) throws {
        let q = query(service, account)
        let attrs: [String: Any] = [kSecValueData as String: value,
                                   kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw SnapNoteKeychainError.status(updated) }
        var insert = q
        insert[kSecValueData as String] = value
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        // A racing add must not cause a silent overwrite of an unrelated item.
        guard added == errSecSuccess else { throw SnapNoteKeychainError.status(added) }
    }
    public func delete(service: String, account: String) throws {
        let status = SecItemDelete(query(service, account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SnapNoteKeychainError.status(status) }
    }
}

/// A dedicated local Keychain item. Never stores tokens in UserDefaults or files.
public struct SnapNoteTokenStore: Sendable {
    public static let service = "local.kkvoice.snapnote"
    public static let account = "bearer-token"
    private let backend: SnapNoteKeychainBackend
    public init(backend: SnapNoteKeychainBackend = SnapNoteSystemKeychain()) { self.backend = backend }
    public func save(_ raw: String) throws {
        let value = try SnapNoteToken.normalize(raw)
        guard let data = value.data(using: .utf8) else { throw SnapNoteKeychainError.corruptData }
        try backend.write(service: Self.service, account: Self.account, value: data)
    }
    public func exists() -> Bool {
        backend.exists(service: Self.service, account: Self.account)
    }
    public func load() throws -> String? {
        guard let data = try backend.read(service: Self.service, account: Self.account) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { throw SnapNoteKeychainError.corruptData }
        return try SnapNoteToken.normalize(value)
    }
    public func delete() throws { try backend.delete(service: Self.service, account: Self.account) }
}

public enum SnapNoteToken {
    public static func normalize(_ raw: String) throws -> String {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("bearer ") {
            normalized = String(normalized.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !normalized.isEmpty else { throw SnapNoteError.notConfigured }
        guard normalized.utf8.count <= 4096,
              normalized.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw SnapNoteError.invalidToken
        }
        return normalized
    }
}
