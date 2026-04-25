import Foundation
import AVFoundation
import ScreenCaptureKit

/// Records meeting audio via ScreenCaptureKit and transcribes via Deepgram.
/// This allows RevyD to work without Granola — capture meetings directly.
final class MeetingRecorder {

    enum RecorderState {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    private(set) var state: RecorderState = .idle
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var startTime: Date?
    private var stream: SCStream?
    private var streamOutput: AudioStreamOutput?

    var onStateChanged: ((RecorderState) -> Void)?
    var onTranscriptReady: ((String, String) -> Void)?  // (title, transcript)

    /// Start recording system audio
    func startRecording(title: String = "Meeting Recording") {
        guard AppSettings.isRecordingAvailable else {
            state = .error("Deepgram API key not configured. Set it in Settings.")
            onStateChanged?(state)
            return
        }

        state = .recording
        startTime = Date()
        onStateChanged?(state)

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("revyd-recording-\(UUID().uuidString).wav")
        recordingURL = url

        // Use ScreenCaptureKit to capture system audio
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else {
                    await MainActor.run {
                        self.state = .error("No display found for audio capture")
                        self.onStateChanged?(self.state)
                    }
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = false
                config.channelCount = 1
                config.sampleRate = 16000 // Deepgram prefers 16kHz

                let output = AudioStreamOutput(outputURL: url)
                self.streamOutput = output

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
                try await stream.startCapture()
                self.stream = stream

                SessionDebugLogger.log("recorder", "Recording started: \(url.path)")
            } catch {
                await MainActor.run {
                    self.state = .error("Failed to start recording: \(error.localizedDescription)")
                    self.onStateChanged?(self.state)
                }
            }
        }
    }

    /// Stop recording and transcribe
    func stopRecording() {
        guard case .recording = state else { return }

        Task {
            if let stream = self.stream {
                try? await stream.stopCapture()
            }
            self.stream = nil
            self.streamOutput?.closeFile()

            await MainActor.run {
                self.state = .transcribing
                self.onStateChanged?(self.state)
            }

            // Transcribe via Deepgram
            guard let url = self.recordingURL else { return }

            do {
                let transcript = try await self.transcribeWithDeepgram(audioURL: url)
                let duration = Date().timeIntervalSince(self.startTime ?? Date())
                let title = "Recording — \(Self.formatDuration(duration))"

                await MainActor.run {
                    self.state = .idle
                    self.onStateChanged?(self.state)
                    self.onTranscriptReady?(title, transcript)
                }

                // Create a meeting from the recording
                self.createMeetingFromRecording(title: title, transcript: transcript)

                // Cleanup audio file
                try? FileManager.default.removeItem(at: url)
            } catch {
                await MainActor.run {
                    self.state = .error("Transcription failed: \(error.localizedDescription)")
                    self.onStateChanged?(self.state)
                }
            }
        }
    }

    // MARK: - Deepgram

    private func transcribeWithDeepgram(audioURL: URL) async throws -> String {
        guard let apiKey = AppSettings.deepgramAPIKey else {
            throw NSError(domain: "RevyD", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Deepgram API key"])
        }

        let audioData = try Data(contentsOf: audioURL)

        var request = URLRequest(url: URL(string: "https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&diarize=true&punctuate=true")!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "RevyD", code: 2, userInfo: [NSLocalizedDescriptionKey: "Deepgram API error"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String else {
            throw NSError(domain: "RevyD", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not parse Deepgram response"])
        }

        return transcript
    }

    // MARK: - Create Meeting

    private func createMeetingFromRecording(title: String, transcript: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        let meeting = Meeting(
            id: UUID().uuidString,
            title: title,
            createdAt: now,
            updatedAt: now,
            summaryMarkdown: nil,
            notesMarkdown: nil,
            transcriptText: transcript,
            attendeesJson: nil,
            debriefJson: nil,
            debriefStatus: "pending",
            syncedAt: now,
            granolaUpdatedAt: nil
        )

        MeetingStore().upsert(meeting)
        KnowledgeIndex().indexMeeting(meeting)
        SessionDebugLogger.log("recorder", "Created meeting from recording: \(title)")
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Audio Stream Output

final class AudioStreamOutput: NSObject, SCStreamOutput {
    private var fileHandle: FileHandle?
    private var outputURL: URL
    private var headerWritten = false

    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        self.fileHandle = FileHandle(forWritingAtPath: outputURL.path)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let dataPointer, length > 0 else { return }
        let data = Data(bytes: dataPointer, count: length)

        if !headerWritten {
            // Write WAV header
            let header = createWAVHeader(dataSize: UInt32.max, sampleRate: 16000, channels: 1, bitsPerSample: 16)
            fileHandle?.write(header)
            headerWritten = true
        }

        fileHandle?.write(data)
    }

    func closeFile() {
        fileHandle?.closeFile()
        fileHandle = nil
    }

    private func createWAVHeader(dataSize: UInt32, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        var header = Data()
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8

        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: (dataSize + 36).littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        return header
    }
}
