import SwiftUI
import Playgrounds
import FoundationModels

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// The model backends a person can send a prompt to.
enum ModelBackend: String, CaseIterable, Identifiable {
    case remote = "Remote"
    case local = "Local"

    var id: Self { self }
}

struct ContentView: View {
    @State private var backend: ModelBackend = .local
    @State private var prompt: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isResponding = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Remote / Local segmented control.
                Picker("Model", selection: $backend) {
                    ForEach(ModelBackend.allCases) { backend in
                        Text(backend.rawValue).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
                // On OS 26, Private Cloud Compute is unavailable, so lock this to Local.
                .disabled(!isRemoteAvailable)

                conversation

                // Prompt entry and send button.
                HStack(spacing: 12) {
                    TextField("Enter a prompt", text: $prompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .onSubmit(send)

                    Button("Send", action: send)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSend)
                }
            }
            .padding()
            .navigationTitle("Apple Intelligence Chat")
            .toolbar {
                Button(role: .destructive, action: clearConversation) {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(messages.isEmpty)
            }
            // Reset the conversation whenever the backend changes.
            .onChange(of: backend) {
                clearConversation()
            }
            .onAppear {
                // Force Local when the remote backend isn't available on this system.
                if !isRemoteAvailable {
                    backend = .local
                }
            }
        }
    }

    /// The conversation, rendered with Markdown support.
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(message.markdown)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(message.id)
                    }

                    if isResponding {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    /// Whether the Private Cloud Compute (remote) backend can be used.
    ///
    /// This is `false` when built against the OS 26 SDK (the symbols don't exist)
    /// or when running on OS 26 (the API isn't available until OS 27).
    private var isRemoteAvailable: Bool {
        #if canImport(FoundationModels, _version: 2.0)
        if #available(anyAppleOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    private func clearConversation() {
        messages.removeAll()
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }

        messages.append(ChatMessage(role: .user, text: text))
        prompt = ""
        isResponding = true

        let backend = self.backend
        Task {
            let reply: String
            do {
                reply = try await respond(to: text, using: backend)
            } catch {
                reply = "⚠️ **Error:** \(error.localizedDescription)"
            }
            messages.append(ChatMessage(role: .assistant, text: reply))
            isResponding = false
        }
    }

    /// Sends the prompt to on-device Apple Intelligence (Local) or Private Cloud Compute (Remote).
    private func respond(to prompt: String, using backend: ModelBackend) async throws -> String {
        let session = languageModelSession(backend: backend)
        let response = try await session.respond(to: prompt)
        return response.content
    }

    func languageModelSession(backend: ModelBackend) -> LanguageModelSession {
        switch backend {
        case .local:
            // On-device Apple Intelligence, available on OS 26 and later.
            LanguageModelSession(model: SystemLanguageModel.default)
        case .remote:
            #if canImport(FoundationModels, _version: 2.0)
            if #available(anyAppleOS 27.0, *) {
                // Server-side Apple Intelligence via Private Cloud Compute (OS 27+).
                LanguageModelSession(model: PrivateCloudComputeLanguageModel())
            } else {
                LanguageModelSession(model: SystemLanguageModel.default)
            }
            #endif
        }
    }
}

/// A single turn in the conversation.
struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant

        var title: String {
            switch self {
            case .user: return "You"
            case .assistant: return "Assistant"
            }
        }
    }

    let id = UUID()
    let role: Role
    let text: String

    /// The message text parsed as Markdown for display.
    var markdown: AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(text)
    }
}

#Preview {
    ContentView()
}
