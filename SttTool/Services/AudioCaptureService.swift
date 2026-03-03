import AVFoundation
import CoreAudio
import Foundation
import os.log

private let audioLogger = Logger(subsystem: "com.voxapp.app", category: "AudioCapture")

actor AudioCaptureService {
    private var audioEngine: AVAudioEngine?
    private var audioSamples: [Float] = []
    private var isRecording = false
    private var onAudioLevel: (@Sendable (Float) -> Void)?
    private var noiseReductionEnabled = false

    private let targetSampleRate: Double = 16000
    // Cap at 5 minutes to bound memory (~4.8MB at 16kHz mono float32)
    private let maxRecordingSeconds: Double = 300
    // Noise gate threshold — RMS below this is considered background noise
    private let noiseGateThreshold: Float = 0.015

    /// Warm up the audio subsystem so the first real recording starts instantly.
    /// Only initializes the HAL — does NOT start the engine (which would
    /// trigger the macOS microphone privacy indicator).
    func warmUp() {
        let engine = AVAudioEngine()
        let node = engine.inputNode
        // Touch the input node's format to force HAL initialization
        _ = node.outputFormat(forBus: 0)
        engine.prepare()
    }

    func startRecording(
        noiseReductionEnabled: Bool = false,
        onAudioLevel: (@Sendable (Float) -> Void)? = nil
    ) throws {
        guard !isRecording else { return }

        self.onAudioLevel = onAudioLevel
        self.noiseReductionEnabled = noiseReductionEnabled
        audioSamples = []
        bufferCount = 0
        audioSamples.reserveCapacity(Int(targetSampleRate) * 60) // Pre-allocate 1 min

        // AudioDeviceManager enforces the system default input device
        // proactively (at startup and on device changes). AVAudioEngine picks
        // up the system default automatically. We intentionally do NOT call
        // AudioUnitSetProperty here — doing so can break the audio tap when
        // setting the same device that's already the system default (CoreAudio
        // quirk that causes 0 buffers to be delivered).
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        audioLogger.notice("Input format: rate=\(inputFormat.sampleRate) ch=\(inputFormat.channelCount)")

        // Validate format — a 0 sample rate means the device is in a bad state
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            audioLogger.error("Invalid input format: rate=\(inputFormat.sampleRate) ch=\(inputFormat.channelCount)")
            throw AudioError.recordingFailed(
                "Microphone returned invalid audio format. The device may be in a bad state — try disconnecting and reconnecting it."
            )
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.formatError
        }

        let converter: AVAudioConverter?
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        } else {
            converter = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            Task {
                await self.processBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.isRecording = true
    }

    func stopRecording() -> AudioData? {
        guard isRecording else { return nil }

        audioLogger.notice("Stopping recording: \(self.audioSamples.count) samples, \(self.bufferCount) buffers received")

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        onAudioLevel = nil
        bufferCount = 0

        let data = AudioData(samples: audioSamples)
        audioSamples = []
        return data
    }

    private var bufferCount = 0

    private func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        targetFormat: AVAudioFormat
    ) {
        bufferCount += 1

        let maxSamples = Int(targetSampleRate * maxRecordingSeconds)
        guard audioSamples.count < maxSamples else { return }
        var samples: [Float]?

        if let converter = converter {
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil, let channelData = convertedBuffer.floatChannelData {
                let count = Int(convertedBuffer.frameLength)
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
            }
        } else {
            guard let channelData = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
        }

        guard var extracted = samples, !extracted.isEmpty else { return }

        // Compute RMS on raw input
        let sumOfSquares = extracted.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(extracted.count))

        // Noise gate: zero out samples below threshold to remove background noise
        if noiseReductionEnabled && rms < noiseGateThreshold {
            for i in extracted.indices { extracted[i] = 0 }
        }

        audioSamples.append(contentsOf: extracted)

        // Send audio level to callback (use gated level so waveform matches output)
        if let callback = onAudioLevel {
            let level = (noiseReductionEnabled && rms < noiseGateThreshold) ? Float(0) : rms
            let normalized = min(level * 5.0, 1.0)
            callback(normalized)
        }
    }
}

enum AudioError: LocalizedError {
    case formatError
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .formatError: return "Failed to create audio format"
        case .recordingFailed(let msg): return "Recording failed: \(msg)"
        }
    }
}
