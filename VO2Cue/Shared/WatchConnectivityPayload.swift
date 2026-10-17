import Foundation

enum WatchConnectivityPayload {
    static let profilesKey = "profiles"
    static let recordKey = "record"
    static let accessKey = "purchaseAccess"
    static let heartPreferencesKey = "heartPreferences"
    static let startRequestKey = "startWorkout"

    static func encodeAccess(_ access: WatchPurchaseAccess) throws -> [String: Any] {
        [accessKey: try JSONEncoder.vo2Cue.encode(access)]
    }

    static func decodeAccess(from payload: [String: Any]) -> WatchPurchaseAccess? {
        guard let data = payload[accessKey] as? Data else { return nil }
        return try? JSONDecoder.vo2Cue.decode(WatchPurchaseAccess.self, from: data)
    }

    static func encodeProfiles(_ profiles: [WorkoutProfile]) throws -> [String: Any] {
        [profilesKey: try JSONEncoder.vo2Cue.encode(profiles)]
    }

    static func decodeProfiles(from payload: [String: Any]) -> [WorkoutProfile]? {
        guard let data = payload[profilesKey] as? Data else { return nil }
        return try? JSONDecoder.vo2Cue.decode([WorkoutProfile].self, from: data)
    }

    static func encodeRecord(_ record: WorkoutRecord) throws -> [String: Any] {
        [recordKey: try JSONEncoder.vo2Cue.encode(record)]
    }

    static func decodeRecord(from payload: [String: Any]) -> WorkoutRecord? {
        guard let data = payload[recordKey] as? Data else { return nil }
        return try? JSONDecoder.vo2Cue.decode(WorkoutRecord.self, from: data)
    }
}
