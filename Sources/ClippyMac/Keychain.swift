import Foundation
import Security

// хранение секретов (ключ Claude API) в Keychain, а не в UserDefaults открытым текстом
enum Keychain {
    private static let service = "com.clippymac.app"

    // пустое значение = удалить запись. статусы не глушим: при сбое пишем warning
    static func set(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let delStatus = SecItemDelete(base as CFDictionary)
        if delStatus != errSecSuccess && delStatus != errSecItemNotFound {
            NSLog("clippy: Keychain delete failed status=\(delStatus)")
        }
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        // доступ только на этом устройстве и только при разблокировке, без синхронизации/бэкапа
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess {
            NSLog("clippy: Keychain add failed status=\(addStatus)")
        }
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
