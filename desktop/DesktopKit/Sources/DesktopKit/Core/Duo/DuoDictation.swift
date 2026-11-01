import AVFoundation
import Perception
import Speech
import SwiftUI

/// The deck's microphone button (and F5): speak, and the words are typed into the focused
/// window, a Linux app or the built-in Terminal. Apple's speech recognition runs on the
/// phone when it can (no audio leaves it); iOS asks for the microphone and speech
/// recognition the first time. Apps can't start iOS's own dictation, so this is LinPad's.
@Perceptible @MainActor
public final class DuoDictation {
    /// The app shares one audio session with the Linux sound and microphone bridges: it
    /// sets the session up for recording (false: the microphone is busy) and puts it back.
    public static var prepareSession: (@MainActor () -> Bool)?
    public static var restoreSession: (@MainActor () -> Void)?
    /// Apple's recognizer stops by itself after about a minute.
    static let maximumDuration: Duration = .seconds(55)

    private(set) var isListening = false
    /// Hold to talk: the mic was slid up, so it keeps listening after the finger lifts.
    var isLocked = false
    /// What has been heard so far, shown above the deck.
    private(set) var transcript = ""
    private(set) var problem: String?

    @PerceptionIgnored weak var controller: DesktopController?
    @PerceptionIgnored private var engine: AVAudioEngine?
    @PerceptionIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @PerceptionIgnored private var task: SFSpeechRecognitionTask?
    @PerceptionIgnored private var timeout: Task<Void, Never>?
    /// Between the button going down and the microphone running (permission checks).
    @PerceptionIgnored private var isStarting = false
    /// Released (or cancelled) before the microphone was running: what to do once it is.
    /// true: cancel, false: type what was heard.
    @PerceptionIgnored private var pendingCancel: Bool?

    func toggle() {
        if isListening { finish() } else { begin() }
    }

    /// Hold to talk: the finger went down on the mic.
    func begin() {
        guard !isListening, !isStarting else { return }
        isLocked = false
        isStarting = true
        pendingCancel = nil
        Task {
            await start()
            isStarting = false
            if let cancelled = pendingCancel {
                pendingCancel = nil
                if cancelled { cancel() } else { finish() }
            }
        }
    }

    /// Lets go of the mic: type what was heard, unless the mic was locked on.
    func release() {
        if isStarting { pendingCancel = false; return }
        guard !isLocked else { return }
        finish()
    }

    /// Slid left: stop and type nothing.
    func cancel() {
        if isStarting { pendingCancel = true; return }
        transcript = ""
        finish()
    }

    private func start() async {
        problem = nil
        guard await Self.authorized() else {
            show("Allow the microphone and speech recognition for LinPad in the iPhone's Settings to dictate.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            show("Speech recognition isn't available right now.")
            return
        }
        let session = AVAudioSession.sharedInstance()
        if let prepare = Self.prepareSession {
            guard prepare() else {
                show("A Linux app is using the microphone.")
                return
            }
        } else {
            try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        }
        try? session.setActive(true)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            restore()
            show("The microphone couldn't start: \(error.localizedDescription)")
            return
        }
        self.engine = engine
        self.request = request
        transcript = ""
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard let self else { return }
                if let text, self.isListening { self.transcript = text }
                if isFinal || (failed && self.isListening) { self.finish() }
            }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.maximumDuration)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// Stops listening and types what was heard.
    func finish() {
        guard isListening else { return }
        isListening = false
        isLocked = false
        timeout?.cancel()
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        engine = nil
        request = nil
        task = nil
        restore()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = ""
        guard !text.isEmpty else { return }
        type(text)
    }

    private func type(_ text: String) {
        guard let controller else { return }
        if controller.deckLinuxTarget != nil, let bridge = controller.linux {
            bridge.type(text)
        } else if let input = controller.deckTextTarget {
            input.insertText(text)
        }
    }

    private func restore() {
        if let restore = Self.restoreSession {
            restore()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        }
    }

    private func show(_ message: String) {
        problem = message
        controller?.notify(message)
    }

    private static func authorized() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}

/// What dictation has heard so far, over the bottom of the desktop.
struct DuoDictationBubble: View {
    let dictation: DuoDictation

    var body: some View {
        WithPerceptionTracking {
            if dictation.isListening {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").symbolEffectCompat()
                    Text(dictation.transcript.isEmpty ? "Listening…" : dictation.transcript)
                        .lineLimit(2)
                        .truncationMode(.head)
                }
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.8)))
                .padding(.bottom, 10)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityLabel(dictation.transcript.isEmpty ? "Listening" : dictation.transcript)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func symbolEffectCompat() -> some View {
        if #available(iOS 17.0, *) {
            symbolEffect(.variableColor.iterative)
        } else {
            self
        }
    }
}
