import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

actor AudioCaptureService {
    private var audioEngine: AVAudioEngine?
    private var audioSamples: [Float] = []
    private var isRecording = false

    private let targetSampleRate: Double = 16000
    // Cap at 5 minutes to bound memory (~4.8MB at 16kHz mono float32)
    private let maxRecordingSeconds: Double = 300

    func startRecording(inputDeviceID: AudioDeviceID? = nil) throws {
        guard !isRecording else { return }

        audioSamples = []
        audioSamples.reserveCapacity(Int(targetSampleRate) * 60) // Pre-allocate 1 min
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Set specific input device if requested
        if let deviceID = inputDeviceID, let audioUnit = inputNode.audioUnit {
            var id = deviceID
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)

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

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false

        let data = AudioData(samples: audioSamples)
        audioSamples = []
        return data
    }

    private func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        targetFormat: AVAudioFormat
    ) {
        let maxSamples = Int(targetSampleRate * maxRecordingSeconds)
        guard audioSamples.count < maxSamples else { return }
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
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
                audioSamples.append(contentsOf: samples)
            }
        } else {
            guard let channelData = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
            audioSamples.append(contentsOf: samples)
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
