import Foundation

struct FeedbackService {
    // Use FormSubmit's invisible-email identifier here, never the recipient address.
    static let formIdentifier = "32a52d593ef58c2abf6a416a3f1c1eeb"

    enum DeliveryError: LocalizedError {
        case unavailable
        case rejected

        var errorDescription: String? {
            switch self {
            case .unavailable: "Feedback is not available yet. Please try again later."
            case .rejected: "Your feedback couldn’t be sent. Please try again."
            }
        }
    }

    func send(subject: String, message: String) async throws {
        guard !Self.formIdentifier.isEmpty,
              let url = URL(string: "https://formsubmit.co/ajax/\(Self.formIdentifier)") else {
            throw DeliveryError.unavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://greggroll.github.io/VO2Cue/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONEncoder().encode([
            "_subject": "VO2Cue: \(subject)",
            "subject": subject,
            "message": message.isEmpty ? "(No message provided)" : message,
            "_url": "https://greggroll.github.io/VO2Cue/"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["success"] as? String == "true" || object["success"] as? Bool == true else {
            throw DeliveryError.rejected
        }
    }
}
