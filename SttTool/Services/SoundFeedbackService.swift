import AppKit

@MainActor
final class SoundFeedbackService {
    static let shared = SoundFeedbackService()

    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: "soundFeedbackEnabled")
    }

    func playStartRecording() {
        play("Tink")
    }

    func playStopRecording() {
        play("Pop")
    }

    func playComplete() {
        play("Glass")
    }

    func playError() {
        play("Basso")
    }

    private func play(_ name: String) {
        guard enabled else { return }
        NSSound(named: name)?.play()
    }

    private init() {
        // Default to enabled
        if UserDefaults.standard.object(forKey: "soundFeedbackEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "soundFeedbackEnabled")
        }
    }
}
