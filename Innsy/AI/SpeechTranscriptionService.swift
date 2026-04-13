//
//  SpeechTranscriptionService.swift
//  Innsy
//

import Foundation
import Speech

enum SpeechTranscriptionService {
    static func transcribe(audioFileURL: URL, locale: Locale = Locale(identifier: "en-US")) async throws -> String {
        let auth = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard auth == .authorized else {
            throw SpeechTranscriptionError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechTranscriptionError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.shouldReportPartialResults = false
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = false
        }

        return try await withCheckedThrowingContinuation { cont in
            var didFinish = false
            recognizer.recognitionTask(with: request) { result, error in
                if didFinish { return }
                if let error {
                    didFinish = true
                    cont.resume(throwing: SpeechTranscriptionError.failed(error.localizedDescription))
                    return
                }
                guard let result, result.isFinal else { return }
                didFinish = true
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    cont.resume(throwing: SpeechTranscriptionError.failed("Empty transcript."))
                } else {
                    cont.resume(returning: text)
                }
            }
        }
    }
}

enum SpeechTranscriptionError: LocalizedError {
    case notAuthorized
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Allow speech recognition in Settings to turn voice into text for Gemma."
        case .unavailable:
            "Speech recognition is not available for this locale."
        case let .failed(msg):
            msg
        }
    }
}
