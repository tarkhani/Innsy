//
//  HuggingFaceGemmaIntentService.swift
//  Innsy
//
//  Hugging Face Inference Endpoints differ by container (TGI vs vLLM vs custom Echo handlers).
//  Custom Gemma handlers may expect chat-shaped `inputs` (nested lists + role/content), not a bare string.
//

import Foundation

enum HuggingFaceGemmaIntentService {
    static func parseIntent(
        transcript: String,
        endpoint: URL,
        accessToken: String,
        uiTripContext: String? = nil,
        facilityCatalogBlock: String
    ) async throws -> BookingIntent {
        let base = normalizeBaseURL(endpoint)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"

        let uiBlock: String = {
            let trimmed = uiTripContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard trimmed.isEmpty == false else { return "" }
            return """

            App UI selections (treat as authoritative facts unless the user clearly contradicts them):
            \(trimmed)
            """
        }()

        let prompt = """
        \(BookingIntent.systemInstruction(facilityCatalogBlock: facilityCatalogBlock))
        Today (for relative dates) is \(df.string(from: Date())).
        \(uiBlock)

        User request (from speech transcript):
        \(transcript)

        Respond with JSON only. No markdown fences; put any narrative in the gemmaInferenceExplanation field, not outside the JSON.
        """

        var attemptsLog: [String] = []
        var requestFactories: [(String, () throws -> URLRequest)] = []

        // vLLM on Hugging Face Inference Endpoints uses OpenAI-compatible `/v1/*` only; try these first.
        let chatModels = chatModelCandidates()
        for model in chatModels {
            let label = "POST /v1/chat/completions model=\(model)"
            requestFactories.append((label, { try Self.openAIChatRequest(baseURL: base, token: accessToken, model: model, prompt: prompt) }))
        }
        for model in chatModels {
            let label = "POST /v1/completions model=\(model)"
            requestFactories.append((label, { try Self.openAICompletionsRequest(baseURL: base, token: accessToken, model: model, prompt: prompt) }))
        }

        // Echo / custom handler: inputs = [[ { role, content: [{type,text}] } ]] — matches apply_chat_template path.
        requestFactories.append(("POST / (Echo: multimodal content parts)", { try Self.postJSON(
            url: base,
            token: accessToken,
            body: Self.echoHandlerBody(prompt: prompt, stringContent: false)
        ) }))
        requestFactories.append(("POST / (Echo: string content)", { try Self.postJSON(
            url: base,
            token: accessToken,
            body: Self.echoHandlerBody(prompt: prompt, stringContent: true)
        ) }))

        requestFactories.append(("POST / (TGI: inputs + parameters)", { try Self.postJSON(
            url: base,
            token: accessToken,
            body: [
                "inputs": prompt,
                "parameters": [
                    "max_new_tokens": 768,
                    "temperature": 0.2,
                    "top_p": 0.9,
                    "return_full_text": false,
                ] as [String: Any],
            ]
        ) }))

        requestFactories.append(("POST / (TGI: inputs only)", { try Self.postJSON(
            url: base,
            token: accessToken,
            body: ["inputs": prompt]
        ) }))

        requestFactories.append(("POST /generate", { try Self.postJSON(
            url: base.appendingPathComponent("generate"),
            token: accessToken,
            body: [
                "inputs": prompt,
                "parameters": ["max_new_tokens": 768, "temperature": 0.2] as [String: Any],
            ]
        ) }))

        var lastError: Error = HuggingFaceGemmaError.noText
        for (label, makeRequest) in requestFactories {
            let request: URLRequest
            do {
                request = try makeRequest()
            } catch {
                attemptsLog.append("\(label): build failed — \(error.localizedDescription)")
                lastError = error
                continue
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    attemptsLog.append("\(label): non-HTTP response")
                    lastError = HuggingFaceGemmaError.badResponse
                    continue
                }
                let bodyPreview = String(data: data, encoding: .utf8) ?? ""
                if (200 ..< 300).contains(http.statusCode) {
                    do {
                        let text = try extractModelText(from: data)
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            attemptsLog.append("\(label): HTTP \(http.statusCode) but empty text. Body: \(String(bodyPreview.prefix(400)))")
                            lastError = HuggingFaceGemmaError.outputEmpty(bodyPreview: String(bodyPreview.prefix(900)))
                            continue
                        }
                        let jsonBlob = isolateJSONObject(in: trimmed)
                        let intent = try JSONDecoder.hotelbeds.decode(BookingIntent.self, from: Data(jsonBlob.utf8))
#if DEBUG
                        debugLogGemmaExchange(prompt: prompt, responseJSON: jsonBlob)
#endif
                        return intent
                    } catch let decodeError as DecodingError {
                        let extracted = (try? extractModelText(from: data)) ?? bodyPreview
                        attemptsLog.append("\(label): bad JSON mapping — \(decodeError.localizedDescription). Snippet: \(String(bodyPreview.prefix(400)))")
                        lastError = HuggingFaceGemmaError.outputNotBookingJSON(text: String(extracted.prefix(1200)), decode: decodeError)
                        continue
                    } catch {
                        attemptsLog.append("\(label): parse error — \(error.localizedDescription)")
                        lastError = error
                        continue
                    }
                }
                attemptsLog.append("\(label): HTTP \(http.statusCode) — \(String(bodyPreview.prefix(300)))")
                lastError = HuggingFaceGemmaError.http(http.statusCode, String(bodyPreview.prefix(600)))
            } catch {
                attemptsLog.append("\(label): \(error.localizedDescription)")
                lastError = error
            }
        }
        throw HuggingFaceGemmaError.allAttemptsFailed(attemptsLog)
    }

    /// Image + user text → full `BookingIntent` JSON (destination, explicit/inferred amenity codes merged into `facilityCodes`, budget, guests, `gemmaInferenceExplanation`).
    static func parseIntentMultimodal(
        userText: String,
        jpegData: Data,
        endpoint: URL,
        accessToken: String,
        uiTripContext: String? = nil,
        facilityCatalogBlock: String
    ) async throws -> BookingIntent {
        let base = normalizeBaseURL(endpoint)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"

        let uiBlock: String = {
            let trimmed = uiTripContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard trimmed.isEmpty == false else { return "" }
            return """

            App UI selections (treat as authoritative facts unless the user clearly contradicts them):
            \(trimmed)
            """
        }()

        let trimmedUser = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let userBlock = trimmedUser.isEmpty ? "(No text — infer everything reasonable from the image and UI context.)" : trimmedUser

        let prompt = """
        \(BookingIntent.systemInstruction(facilityCatalogBlock: facilityCatalogBlock, hasReferenceImage: true))
        Today (for relative dates) is \(df.string(from: Date())).
        \(uiBlock)

        MULTIMODAL INPUT: There is a reference image AND user text below. **Whenever the text contradicts the photo, the text wins**—including destination, dates, budget, guests, and amenities. Geography (country, city, region) comes from the text unless it is silent on location. If the user says “UK”, “United Kingdom”, “England”, “London”, “Britain”, etc., set `countryCode` and destination to that—**ignore** whether the photo looks like Thailand, Maldives, or Alps. Use the image for `inferredAmenityCodes` (and explanation) only where it **does not conflict** with what they said.

        User text (highest weight on any disagreement):
        \(userBlock)

        Image: add matching CATALOG codes to `inferredAmenityCodes` when aligned with the text; never override spoken facts with the picture.

        Respond with JSON only. No markdown fences, no text outside the JSON object.
        """

        let b64 = jpegData.base64EncodedString()
        let dataURI = "data:image/jpeg;base64,\(b64)"
        let gemmaImage: [String: Any] = ["type": "image", "url": dataURI]
        let textPart: [String: Any] = ["type": "text", "text": prompt]

        var attemptsLog: [String] = []
        var requestFactories: [(String, () throws -> URLRequest)] = []

        let chatModels = chatModelCandidates()
        for model in chatModels {
            let label = "POST /v1/chat/completions (vision) model=\(model)"
            requestFactories.append((label, { try Self.openAIChatVisionRequest(
                baseURL: base,
                token: accessToken,
                model: model,
                dataURI: dataURI,
                prompt: prompt,
                maxTokens: 1024
            ) }))
        }

        // Text before image so the model sees location rules and transcript before the (possibly misleading) photo.
        for (parts, label) in [([textPart, gemmaImage], "POST / (Echo: text then image)"), ([gemmaImage, textPart], "POST / (Echo: image then text)")] {
            requestFactories.append((label, { try Self.postJSON(
                url: base,
                token: accessToken,
                body: Self.echoMultimodalBody(contentParts: parts, maxNewTokens: 1024)
            ) }))
        }

        let openAIImage: [String: Any] = ["type": "image_url", "image_url": ["url": dataURI] as [String: Any]]
        requestFactories.append(("POST / (Echo: OpenAI image_url)", { try Self.postJSON(
            url: base,
            token: accessToken,
            body: Self.echoMultimodalBody(contentParts: [textPart, openAIImage], maxNewTokens: 1024)
        ) }))

        var lastError: Error = HuggingFaceGemmaError.noText
        for (label, makeRequest) in requestFactories {
            let request: URLRequest
            do {
                request = try makeRequest()
            } catch {
                attemptsLog.append("\(label): build failed — \(error.localizedDescription)")
                lastError = error
                continue
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    attemptsLog.append("\(label): non-HTTP response")
                    lastError = HuggingFaceGemmaError.badResponse
                    continue
                }
                let bodyPreview = String(data: data, encoding: .utf8) ?? ""
                if (200 ..< 300).contains(http.statusCode) {
                    do {
                        let text = try extractModelText(from: data)
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            attemptsLog.append("\(label): HTTP \(http.statusCode) but empty text. Body: \(String(bodyPreview.prefix(400)))")
                            lastError = HuggingFaceGemmaError.outputEmpty(bodyPreview: String(bodyPreview.prefix(900)))
                            continue
                        }
                        let jsonBlob = isolateJSONObject(in: trimmed)
                        let intent = try JSONDecoder.hotelbeds.decode(BookingIntent.self, from: Data(jsonBlob.utf8))
#if DEBUG
                        debugLogGemmaExchange(prompt: prompt, responseJSON: jsonBlob)
#endif
                        return intent
                    } catch let decodeError as DecodingError {
                        let extracted = (try? extractModelText(from: data)) ?? bodyPreview
                        attemptsLog.append("\(label): bad JSON mapping — \(decodeError.localizedDescription). Snippet: \(String(bodyPreview.prefix(400)))")
                        lastError = HuggingFaceGemmaError.outputNotBookingJSON(text: String(extracted.prefix(1200)), decode: decodeError)
                        continue
                    } catch {
                        attemptsLog.append("\(label): parse error — \(error.localizedDescription)")
                        lastError = error
                        continue
                    }
                }
                attemptsLog.append("\(label): HTTP \(http.statusCode) — \(String(bodyPreview.prefix(300)))")
                lastError = HuggingFaceGemmaError.http(http.statusCode, String(bodyPreview.prefix(600)))
            } catch {
                attemptsLog.append("\(label): \(error.localizedDescription)")
                lastError = error
            }
        }
        throw HuggingFaceGemmaError.allAttemptsFailed(attemptsLog)
    }

    // MARK: - Echo custom handler body

    private static func echoMultimodalBody(contentParts: [[String: Any]], maxNewTokens: Int) -> [String: Any] {
        let userMessage: [String: Any] = [
            "role": "user",
            "content": contentParts,
        ]
        let wrapped: [Any] = [
            [userMessage],
        ]
        return [
            "inputs": wrapped,
            "parameters": [
                "max_new_tokens": maxNewTokens,
                "temperature": 0.2,
                "top_p": 0.9,
            ] as [String: Any],
        ]
    }

    /// Mirrors Python `_messages_to_chat`: `inputs` is either `[messages]` or `[[messages]]`.
    private static func echoHandlerBody(prompt: String, stringContent: Bool) -> [String: Any] {
        let content: Any = stringContent
            ? prompt
            : [["type": "text", "text": prompt] as [String: Any]]
        let userMessage: [String: Any] = [
            "role": "user",
            "content": content,
        ]
        let wrapped: [Any] = [
            [userMessage],
        ]
        return [
            "inputs": wrapped,
            "parameters": [
                "max_new_tokens": 768,
                "temperature": 0.2,
                "top_p": 0.9,
            ] as [String: Any],
        ]
    }

    // MARK: - URL / requests

    private static func normalizeBaseURL(_ url: URL) -> URL {
        var s = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") {
            s.removeLast()
        }
        return URL(string: s) ?? url
    }

    /// OpenAI-compatible routes live under `…/v1/…`. HF docs sometimes give a base URL that already ends with `/v1`.
    private static func openAIAPIRoot(from base: URL) -> URL {
        var s = base.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.lowercased().hasSuffix("/v1") {
            return URL(string: s) ?? base
        }
        let root = URL(string: s) ?? base
        return root.appendingPathComponent("v1")
    }

    private static func postJSON(url: URL, token: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func openAIChatRequest(baseURL: URL, token: String, model: String, prompt: String) throws -> URLRequest {
        let url = openAIAPIRoot(from: baseURL).appendingPathComponent("chat").appendingPathComponent("completions")
        // vLLM + HF IE examples use chat-shaped `content` as a list of parts; both layouts are widely accepted.
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt] as [String: Any],
                    ],
                ],
            ],
            "max_tokens": 768,
            "temperature": 0.2,
            "stream": false,
        ]
        return try postJSON(url: url, token: token, body: body)
    }

    private static func openAIChatVisionRequest(
        baseURL: URL,
        token: String,
        model: String,
        dataURI: String,
        prompt: String,
        maxTokens: Int
    ) throws -> URLRequest {
        let url = openAIAPIRoot(from: baseURL).appendingPathComponent("chat").appendingPathComponent("completions")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": dataURI] as [String: Any]],
                    ],
                ],
            ],
            "max_tokens": maxTokens,
            "temperature": 0.2,
            "stream": false,
        ]
        return try postJSON(url: url, token: token, body: body)
    }

    private static func openAICompletionsRequest(baseURL: URL, token: String, model: String, prompt: String) throws -> URLRequest {
        let url = openAIAPIRoot(from: baseURL).appendingPathComponent("completions")
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "max_tokens": 768,
            "temperature": 0.2,
            "stream": false,
        ]
        return try postJSON(url: url, token: token, body: body)
    }

    private static func chatModelCandidates() -> [String] {
        let configured = Secrets.huggingFaceChatModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if configured.isEmpty == false { return [configured] }
        // vLLM requires the served model id (Hub repo id or `--served-model-name`). "tgi" is only for legacy TGI OpenAI adapters.
        return [
            "google/gemma-3-4b-it",
            "google/gemma-3-12b-it",
            "google/gemma-3-27b-it",
            "google/gemma-2-9b-it",
            "google/gemma-2-2b-it",
            "tgi",
        ]
    }

    // MARK: - Response parsing

    /// OpenAI chat `message.content` is usually a string; some stacks return a list of content parts.
    private static func stringFromOpenAIAssistantContent(_ content: Any?) -> String? {
        guard let content else { return nil }
        if let s = content as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : s
        }
        guard let arr = content as? [Any] else { return nil }
        var parts: [String] = []
        for item in arr {
            if let s = item as? String, s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                parts.append(s)
                continue
            }
            guard let d = item as? [String: Any] else { continue }
            if let t = d["text"] as? String, t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                parts.append(t)
            }
        }
        let joined = parts.joined()
        return joined.isEmpty ? nil : joined
    }

    private static func extractModelText(from data: Data) throws -> String {
        let obj = try JSONSerialization.jsonObject(with: data)

        if let s = obj as? String {
            return s
        }

        if let arr = obj as? [Any] {
            if let first = arr.first as? [String: Any] {
                if let t = first["generated_text"] as? String { return t }
            }
            if let inner = arr.first as? [Any],
               let first = inner.first as? [String: Any],
               let t = first["generated_text"] as? String {
                return t
            }
            if let parts = arr as? [[String: Any]] {
                var buf = ""
                for p in parts {
                    if let t = p["generated_text"] as? String { buf += t }
                }
                if buf.isEmpty == false { return buf }
            }
        }

        if let dict = obj as? [String: Any] {
            if let t = dict["generated_text"] as? String { return t }

            if let choices = dict["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any] {
                if let content = stringFromOpenAIAssistantContent(msg["content"]) {
                    return content
                }
            }
            if let choices = dict["choices"] as? [[String: Any]],
               let text = choices.first?["text"] as? String {
                return text
            }
            if let choices = dict["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                return content
            }

            if let out = dict["output"] as? String { return out }
            if let out = dict["outputs"] as? [String],
               let first = out.first {
                return first
            }
        }

        if let text = String(data: data, encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return text
        }
        throw HuggingFaceGemmaError.noText
    }

    private static func isolateJSONObject(in text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fenceStripped = stripMarkdownCodeFence(trimmed)
        if let start = fenceStripped.firstIndex(of: "{"), let end = fenceStripped.lastIndex(of: "}") {
            return String(fenceStripped[start ... end])
        }
        return fenceStripped
    }

    private static func stripMarkdownCodeFence(_ s: String) -> String {
        var t = s
        if t.hasPrefix("```json") {
            t.removeFirst(7)
        } else if t.hasPrefix("```") {
            t.removeFirst(3)
        }
        if t.hasSuffix("```") {
            t.removeLast(3)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

#if DEBUG
    /// Only console output in DEBUG: full text prompt and parsed booking JSON (no truncation).
    private static func debugLogGemmaExchange(prompt: String, responseJSON: String) {
        print("--- Innsy Gemma: full prompt (all text sent to the model) ---\n\(prompt)\n--- end prompt ---")
        print("--- Innsy Gemma: model JSON ---\n\(responseJSON)\n--- end model JSON ---")
    }
#endif
}

enum HuggingFaceGemmaError: LocalizedError {
    case badResponse
    case noText
    case http(Int, String)
    case outputEmpty(bodyPreview: String)
    case outputNotBookingJSON(text: String, decode: Error)
    case allAttemptsFailed([String])

    var errorDescription: String? {
        switch self {
        case .badResponse:
            "Invalid response from Hugging Face endpoint."
        case .noText:
            "The endpoint returned no parseable text."
        case let .http(code, body):
            "Hugging Face HTTP \(code): \(body)"
        case let .outputEmpty(preview):
            "The model responded but text was empty. Raw (truncated): \(preview)"
        case let .outputNotBookingJSON(text, decode):
            "Model returned text that is not valid booking JSON. Decode: \(decode.localizedDescription). Text (truncated): \(String(text.prefix(800)))"
        case let .allAttemptsFailed(lines):
            """
            Hugging Face: all request variants failed. Details:
            \(lines.joined(separator: "\n"))
            For vLLM endpoints, set `huggingFaceChatModelId` in Secrets.swift to the exact model id your endpoint serves (see HF endpoint settings). Legacy `POST /` tries may 404 on vLLM-only hosts — that is normal.
            """
        }
    }
}
