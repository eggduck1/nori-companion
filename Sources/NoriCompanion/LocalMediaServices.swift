import AVFoundation
import Combine
import Foundation
import ImageIO
import Speech
import Vision

@MainActor
final class LocalMediaServices: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var mediaStatus = ""

    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var stopListeningTask: Task<Void, Never>?
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var photoDelegate: PhotoCaptureDelegate?
    private var photoContinuation: CheckedContinuation<Data, Error>?
    private var onTranscript: ((String) -> Void)?

    func startListening(onTranscript: @escaping (String) -> Void) async {
        guard !isListening else { return }
        guard recognitionRequest == nil else {
            mediaStatus = "Wait for the current transcription to finish."
            return
        }
        guard await requestSpeechPermission(),
              await requestMicrophonePermission() else {
            mediaStatus = "Allow Speech Recognition and Microphone access in System Settings to use voice."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            mediaStatus = "Speech recognition is currently unavailable."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            mediaStatus = "On-device speech recognition is unavailable for this language. Audio will not be sent to a server."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            mediaStatus = "Could not start the microphone: \(error.localizedDescription)"
            return
        }

        recognitionRequest = request
        self.onTranscript = onTranscript
        isListening = true
        mediaStatus = "Listening on this Mac. Select Stop & send when you’re done."
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.recognitionRequest != nil else { return }
                if let error {
                    self.finishListening()
                    self.mediaStatus = "Speech recognition failed: \(error.localizedDescription)"
                } else if let result, result.isFinal {
                    let transcript = result.bestTranscription.formattedString
                    let callback = self.onTranscript
                    self.finishListening()
                    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        self.mediaStatus = "No speech was recognized."
                        return
                    }
                    self.mediaStatus = "Sending your transcript to Nori."
                    callback?(transcript)
                }
            }
        }

        stopListeningTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            self?.cancelListeningAfterLimit()
        }
    }

    func stopListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isListening = false
        isFinalizing = true
        mediaStatus = "Finishing transcription…"
        stopListeningTask?.cancel()
        stopListeningTask = nil
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    func setStatus(_ status: String) {
        mediaStatus = status
    }

    func analyzeCameraScene() async throws -> String {
        guard await requestCameraPermission() else {
            throw LocalMediaError.permission("Allow Camera access in System Settings to analyze a scene.")
        }
        guard let camera = AVCaptureDevice.default(for: .video) else {
            throw LocalMediaError.unavailable("No compatible camera was found.")
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .photo
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw LocalMediaError.unavailable("Could not configure the camera input.")
        }
        session.addInput(input)
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw LocalMediaError.unavailable("Could not configure the camera.")
        }
        session.addOutput(output)
        session.commitConfiguration()
        captureSession = session
        photoOutput = output
        session.startRunning()
        defer {
            session.stopRunning()
            captureSession = nil
            photoOutput = nil
        }

        let imageData = try await withCheckedThrowingContinuation { continuation in
            photoContinuation = continuation
            photoDelegate = PhotoCaptureDelegate { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.photoContinuation?.resume(with: result)
                    self.photoContinuation = nil
                    self.photoDelegate = nil
                }
            }
            guard let photoDelegate else {
                continuation.resume(throwing: LocalMediaError.unavailable("Could not start camera capture."))
                return
            }
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: photoDelegate)
        }
        return try Self.describeScene(in: imageData)
    }

    private func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    private func requestSpeechPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        guard status == .notDetermined else { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func finishListening() {
        stopListeningTask?.cancel()
        stopListeningTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        isFinalizing = false
    }

    private func cancelListeningAfterLimit() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        onTranscript = nil
        isListening = false
        isFinalizing = false
        stopListeningTask = nil
        mediaStatus = "Stopped after 45 seconds. No transcript was sent."
    }

    nonisolated private static func describeScene(in imageData: Data) throws -> String {
        let classification = VNClassifyImageRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(data: imageData)
        try handler.perform([classification, faces])

        let labels = (classification.results ?? [])
            .filter { $0.confidence >= 0.18 }
            .prefix(5)
            .map { $0.identifier }
        let faceCount = faces.results?.count ?? 0
        let objects = labels.isEmpty ? "No clear object labels were found." : "Likely objects or scene: \(labels.joined(separator: ", "))."
        let people = faceCount == 0 ? "No faces detected." : "\(faceCount) face\(faceCount == 1 ? "" : "s") detected; identities are not recognized."
        return "\(objects) \(people) Image analysis ran locally on this Mac; no image was saved or sent."
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            completion(.success(data))
        } else {
            completion(.failure(LocalMediaError.unavailable("The camera did not return an image.")))
        }
    }
}

private enum LocalMediaError: LocalizedError {
    case permission(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .permission(let message), .unavailable(let message): message
        }
    }
}
