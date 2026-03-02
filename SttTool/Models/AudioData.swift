import Foundation

struct AudioData {
    let samples: [Float]
    let sampleRate: Double = 16000

    var duration: TimeInterval {
        Double(samples.count) / sampleRate
    }

    var isTooShort: Bool {
        duration < 0.5
    }

    var isTooLong: Bool {
        duration > 1800
    }
}
