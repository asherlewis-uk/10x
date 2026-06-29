import Foundation

enum SignupBonusClaimStore {
    nonisolated private static let service = "\(AuthKeychainStore.defaultService).device-fingerprint"
    nonisolated private static let signupBonusClaimKey = "signup_bonus_local_claim"

    struct Record: Sendable {
        let userId: String?
        let claimedAt: String
    }

    nonisolated static func record() -> Record? {
        guard let raw = AuthKeychainStore.string(for: signupBonusClaimKey, service: service),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let userId = object["userId"] as? String
        guard let claimedAt = object["claimedAt"] as? String else {
            return nil
        }
        return Record(userId: userId, claimedAt: claimedAt)
    }

    nonisolated static func markClaimed(userId: String?) {
        let payload: [String: String] = [
            "claimedAt": ISO8601DateFormatter().string(from: Date()),
            "userId": normalizedUserId(userId) ?? "",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        AuthKeychainStore.set(raw, for: signupBonusClaimKey, service: service)
    }

    nonisolated static func isBlocked(for userId: String?) -> Bool {
        guard let record = record() else { return false }
        guard let recordedUserId = normalizedUserId(record.userId) else { return true }
        guard let currentUserId = normalizedUserId(userId) else { return true }
        return recordedUserId != currentUserId
    }

    private nonisolated static func normalizedUserId(_ userId: String?) -> String? {
        guard let userId else { return nil }
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
