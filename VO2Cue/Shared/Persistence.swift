import Foundation

enum Persistence {
    static func load<Value: Decodable>(
        _ type: Value.Type,
        fileName: String,
        fileManager: FileManager = .default
    ) -> Value? {
        guard let url = try? fileURL(fileName: fileName, fileManager: fileManager),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.vo2Cue.decode(Value.self, from: data)
    }

    static func save<Value: Encodable>(
        _ value: Value,
        fileName: String,
        protection: Data.WritingOptions = .completeFileProtection,
        fileManager: FileManager = .default
    ) throws {
        let url = try fileURL(fileName: fileName, fileManager: fileManager)
        let data = try JSONEncoder.vo2Cue.encode(value)
        try data.write(to: url, options: [.atomic, protection])
    }

    private static func fileURL(fileName: String, fileManager: FileManager) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "VO2Cue", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: fileName)
    }
}

extension JSONEncoder {
    static var vo2Cue: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var vo2Cue: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
