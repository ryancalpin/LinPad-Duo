import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Answers the guest's `ask` command (Core/Duo/DuoGuestTools) with Apple's on-device
/// language model (Foundation Models, iOS 26 and later). Nothing leaves the phone and no
/// network is needed. `ask` writes `<id>.question` and an empty `<id>.answer` under
/// /tmp/linpad-duo/ask; the answer goes into that file followed by a status line and an end
/// marker. iOS runs the model only while LinPad is in front.
@MainActor
final class DuoAskService {
    static let shared = DuoAskService()
    private static let logger = Logger(subsystem: "DesktopKit", category: "DuoAsk")
    static let endMarker = "__LINPAD_END__"
    static let instructions = """
        You answer questions typed into a Linux terminal on an iPhone running Alpine Linux. \
        Reply in plain text for a terminal: no Markdown headings, bold or tables. Keep answers \
        short unless asked for detail. Put commands on their own lines so they can be copied.
        """

    private var askURL: URL?
    private var answering: Set<String> = []

    func start(guestRoot: URL?) {
        askURL = guestRoot?.appendingPathComponent(String(DuoGuestTools.askDirectory.dropFirst()), isDirectory: true)
    }

    /// One look for new questions; called on every job-list tick. Answers run on their own,
    /// so a slow answer doesn't hold up the job list.
    func poll() {
        guard let askURL else { return }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: askURL.path)) ?? []
        for file in files where file.hasSuffix(".question") {
            let id = String(file.dropLast(".question".count))
            guard !answering.contains(id) else { continue }
            let answerURL = askURL.appendingPathComponent(id + ".answer")
            // Only an empty answer file is a question still waiting.
            guard let size = try? answerURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == 0,
                  let question = try? String(contentsOf: askURL.appendingPathComponent(file), encoding: .utf8)
            else { continue }
            answering.insert(id)
            Task {
                let (text, ok) = await answer(question)
                write(text, ok: ok, to: answerURL)
                answering.remove(id)
            }
        }
    }

    private func answer(_ question: String) async -> (String, Bool) {
        guard DuoSettings.isOn(DuoSettings.onDeviceAIKey) else {
            return ("ask is off: turn on Settings › iPhone Duo › On-device AI in LinPad.", false)
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                do {
                    let session = LanguageModelSession(instructions: Self.instructions)
                    let response = try await session.respond(to: question)
                    return (response.content, true)
                } catch {
                    Self.logger.error("ask failed: \(error.localizedDescription, privacy: .public)")
                    return ("The on-device model couldn't answer: \(error.localizedDescription)", false)
                }
            case .unavailable(let reason):
                return (Self.explanation(for: reason), false)
            }
        }
        #endif
        return ("ask needs iOS 26 or later with Apple Intelligence.", false)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func explanation(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "This device can't run Apple's on-device model."
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in the iPhone's Settings › Apple Intelligence & Siri, then try again."
        case .modelNotReady: "Apple's on-device model is still downloading. Try again in a few minutes."
        @unknown default: "Apple's on-device model isn't available right now."
        }
    }
    #endif

    /// Into the file `ask` created (the fakefs only lets the app change files the guest made).
    private func write(_ text: String, ok: Bool, to url: URL) {
        let body = text.hasSuffix("\n") ? text : text + "\n"
        let data = Data((body + "__LINPAD_STATUS__ \(ok ? "ok" : "error")\n\(Self.endMarker)\n").utf8)
        let fd = open(url.path, O_WRONLY | O_TRUNC | O_CLOEXEC)
        guard fd >= 0 else { return }
        _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }
}
