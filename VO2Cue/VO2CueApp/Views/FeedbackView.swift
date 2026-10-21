import SwiftUI

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sent = false

    private var trimmedSubject: String { subject.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Report an issue, request a feature, or just say hi. Positive feedback is very much appreciated!")
                }
                Section {
                    TextField("Subject", text: $subject)
                        .accessibilityIdentifier("feedbackSubject")
                    TextField("Message (optional)", text: $message, axis: .vertical)
                        .lineLimit(6...12)
                        .accessibilityIdentifier("feedbackMessage")
                } footer: {
                    Text("Only your subject and message are sent to the developer through FormSubmit. Workout and Health data aren’t attached. Please don’t include sensitive information.")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(isSending)
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        send()
                    } label: {
                        if isSending {
                            ProgressView().accessibilityLabel("Sending feedback")
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(trimmedSubject.isEmpty || isSending)
                }
            }
            .interactiveDismissDisabled(isSending)
            .alert("Thanks for reaching out!", isPresented: $sent) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your feedback has been sent. I appreciate your support!")
            }
        }
    }

    private func send() {
        isSending = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSending = false }
            do {
                try await FeedbackService().send(
                    subject: trimmedSubject,
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                sent = true
            } catch let error as FeedbackService.DeliveryError {
                errorMessage = error.localizedDescription
            } catch {
                // Keep the draft intact and never expose a provider response or recipient address.
                errorMessage = "Your feedback couldn’t be sent. Check your connection and try again."
            }
        }
    }
}
