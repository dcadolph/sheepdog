import Foundation
import Security

import SheepdogCore

// Keychain stores one AccountRecord per service as a generic password in the login keychain.
// The data protection keychain needs a team-signed entitlement, which ad-hoc builds do not have.
enum Keychain {
    // service is the Keychain service name for account records.
    static let service = "com.dcadolph.sheepdog.account"

    // load returns the stored record for a service, or nil when there is none or it does not decode.
    static func load(_ kind: AccountKind) -> AccountRecord? {
        var query = baseQuery(kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(AccountRecord.self, from: data)
    }

    // save replaces the stored record for the record's service.
    static func save(_ record: AccountRecord) throws {
        let data = try JSONEncoder().encode(record)
        SecItemDelete(baseQuery(record.kind) as CFDictionary)
        var item = baseQuery(record.kind)
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Sheepdog \(record.kind.label) sign-in"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }

    // delete removes the stored record for a service.
    static func delete(_ kind: AccountKind) {
        SecItemDelete(baseQuery(kind) as CFDictionary)
    }

    // baseQuery identifies the item for a service.
    private static func baseQuery(_ kind: AccountKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
        ]
    }
}
