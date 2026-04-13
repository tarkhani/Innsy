//
//  HotelBookingViewModel.swift
//  Innsy
//

import Foundation

@MainActor
final class HotelBookingViewModel: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var intent: BookingIntent?
    /// Human-readable facility labels for `intent.facilityCodes` (trip summary); keyed by code.
    @Published private(set) var intentFacilityDisplayNamesByCode: [Int: String] = [:]
    @Published var cards: [HotelOfferCard] = []
    @Published var alertMessage: String?
    @Published var lastBookingReference: String?
    /// Shown on the results screen when the search succeeded but `cards` is empty (alert alone is easy to miss).
    @Published var emptyResultsExplanation: String?
    @Published private(set) var isRecording = false

    /// Cancels in-flight search work when the user pops back from Matches during parsing/fetching.
    private var searchTask: Task<Void, Never>?
    private var searchGeneration: UInt64 = 0

    enum Phase: Equatable {
        case idle
        case parsingAudio
        case fetchingHotels
        case ready
        case booking
    }

    private let recorder = VoiceRecorder()
    private var pipeline: HotelbedsHotelPipeline {
        let env = HotelbedsEnvironment(useTestHosts: Secrets.hotelbedsUseTestEnvironment)
        let client = HotelbedsAPIClient(
            environment: env,
            apiKey: Secrets.hotelbedsAPIKey,
            secret: Secrets.hotelbedsSecret
        )
        return HotelbedsHotelPipeline(client: client)
    }

    /// Facility catalog text for Gemma (HF): **only** `GemmaFacilityAllowlist.json` (never the downloaded Hotelbeds codebook).
    private func loadFacilityCatalogForLLMPrompt() async -> String {
        GemmaFacilityAllowlist.promptCatalogText()
    }

    /// Call when the user leaves the Matches screen while a search is still running (back button).
    func cancelSearchBecauseUserNavigatedBack() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
        guard phase == .parsingAudio || phase == .fetchingHotels else { return }
        phase = .idle
        intent = nil
        intentFacilityDisplayNamesByCode = [:]
        cards = []
        emptyResultsExplanation = nil
        alertMessage = nil
    }

    @discardableResult
    private func beginTrackedSearch(_ work: @escaping @MainActor (UInt64) async -> Void) -> Task<Void, Never> {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
        let gen = searchGeneration
        let t = Task { @MainActor in
            defer {
                if self.searchGeneration == gen {
                    self.searchTask = nil
                }
            }
            await work(gen)
        }
        searchTask = t
        return t
    }

    private func isSearchStale(_ gen: UInt64) -> Bool {
        gen != searchGeneration || Task.isCancelled
    }

    private func throwIfSearchStale(_ gen: UInt64) throws {
        if isSearchStale(gen) { throw CancellationError() }
    }

    func recordTap(attachmentJPEG: Data? = nil, tripContext: TripPromptContext) async {
        if recorder.isRecording {
            recorder.stop()
            isRecording = false
            guard let file = recorder.lastFileURL else {
                alertMessage = "No recording file."
                return
            }
            let ui = tripContext.llmAppendix()
            scheduleRunPipeline(audioURL: file, attachmentJPEG: attachmentJPEG, uiTripContext: ui)
        } else {
            let ok = await recorder.requestPermission()
            guard ok else {
                alertMessage = "Microphone access is required."
                return
            }
            do {
                try recorder.start()
                isRecording = true
            } catch {
                isRecording = false
                alertMessage = error.localizedDescription
            }
        }
    }

    func submitTextPrompt(_ prompt: String, attachmentJPEG: Data? = nil, tripContext: TripPromptContext) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            alertMessage = "Please type your hotel request first."
            return
        }

        let uiTrip = tripContext.llmAppendix()

        intent = nil
        intentFacilityDisplayNamesByCode = [:]
        cards = []
        emptyResultsExplanation = nil
        phase = .parsingAudio

        let task = beginTrackedSearch { gen in
            do {
                guard Secrets.hotelbedsAPIKey.starts(with: "YOUR_") == false else {
                    throw NSError(domain: "Innsy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Set Secrets.hotelbedsAPIKey and hotelbedsSecret."])
                }
                let facilityCatalog = await self.loadFacilityCatalogForLLMPrompt()
                try self.throwIfSearchStale(gen)
                let parsed: BookingIntent
                do {
                    parsed = try await self.parseIntentFromText(
                        trimmed,
                        uiTripContext: uiTrip,
                        attachmentJPEG: attachmentJPEG,
                        facilityCatalogBlock: facilityCatalog
                    )
                } catch {
                    if let jpeg = attachmentJPEG, jpeg.isEmpty == false {
                        let hfToken = ResolvedLLMKeys.huggingFaceAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
                        if hfToken.isEmpty == false, let endpoint = URL(string: Secrets.huggingFaceGemmaEndpoint) {
                            parsed = try await HuggingFaceGemmaIntentService.parseIntent(
                                transcript: trimmed,
                                endpoint: endpoint,
                                accessToken: hfToken,
                                uiTripContext: uiTrip,
                                facilityCatalogBlock: facilityCatalog
                            )
                        } else {
                            throw error
                        }
                    } else {
                        throw error
                    }
                }
                try self.throwIfSearchStale(gen)
                try await self.runHotelFetchPipeline(
                    parsed: parsed,
                    facilityMatchText: trimmed,
                    activeGeneration: gen
                )
            } catch is CancellationError {
                self.handleSearchCancelled(expectedGeneration: gen)
            } catch {
                guard self.searchGeneration == gen else { return }
                self.phase = .idle
                self.emptyResultsExplanation = nil
                self.alertMessage = Self.describe(error: error)
            }
        }
        await task.value
    }

    private func scheduleRunPipeline(audioURL: URL, attachmentJPEG: Data? = nil, uiTripContext: String) {
        intent = nil
        intentFacilityDisplayNamesByCode = [:]
        cards = []
        emptyResultsExplanation = nil
        phase = .parsingAudio

        beginTrackedSearch { gen in
            do {
                guard Secrets.hotelbedsAPIKey.starts(with: "YOUR_") == false else {
                    throw NSError(domain: "Innsy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Set Secrets.hotelbedsAPIKey and hotelbedsSecret."])
                }
                let facilityCatalog = await self.loadFacilityCatalogForLLMPrompt()
                try self.throwIfSearchStale(gen)
                let (parsed, transcript) = try await self.parseIntentFromAudio(
                    audioURL,
                    uiTripContext: uiTripContext,
                    attachmentJPEG: attachmentJPEG,
                    facilityCatalogBlock: facilityCatalog
                )
                try self.throwIfSearchStale(gen)
                let facilityText = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
                let matchText = (facilityText?.isEmpty == false) ? facilityText : nil
                try await self.runHotelFetchPipeline(
                    parsed: parsed,
                    facilityMatchText: matchText,
                    activeGeneration: gen
                )
            } catch is CancellationError {
                self.handleSearchCancelled(expectedGeneration: gen)
            } catch {
                guard self.searchGeneration == gen else { return }
                self.phase = .idle
                self.emptyResultsExplanation = nil
                self.alertMessage = Self.describe(error: error)
            }
        }
    }

    private func handleSearchCancelled(expectedGeneration gen: UInt64) {
        guard searchGeneration == gen else { return }
        phase = .idle
        intent = nil
        intentFacilityDisplayNamesByCode = [:]
        cards = []
        emptyResultsExplanation = nil
        alertMessage = nil
    }

    private func parseIntentFromAudio(
        _ audioURL: URL,
        uiTripContext: String,
        attachmentJPEG: Data? = nil,
        facilityCatalogBlock: String
    ) async throws -> (BookingIntent, String?) {
        let hfToken = ResolvedLLMKeys.huggingFaceAccessToken
        guard hfToken.isEmpty == false else {
            throw missingAPIKeysError()
        }
        guard let endpoint = URL(string: Secrets.huggingFaceGemmaEndpoint) else {
            throw NSError(domain: "Innsy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Secrets.huggingFaceGemmaEndpoint URL."])
        }
        let hasImage = attachmentJPEG.map { !$0.isEmpty } ?? false

        let transcript = try await SpeechTranscriptionService.transcribe(audioFileURL: audioURL)
        if hasImage, let jpeg = attachmentJPEG {
            do {
                let intent = try await HuggingFaceGemmaIntentService.parseIntentMultimodal(
                    userText: transcript,
                    jpegData: jpeg,
                    endpoint: endpoint,
                    accessToken: hfToken,
                    uiTripContext: uiTripContext,
                    facilityCatalogBlock: facilityCatalogBlock
                )
                return (intent, transcript)
            } catch {
                return (
                    try await HuggingFaceGemmaIntentService.parseIntent(
                        transcript: transcript,
                        endpoint: endpoint,
                        accessToken: hfToken,
                        uiTripContext: uiTripContext,
                        facilityCatalogBlock: facilityCatalogBlock
                    ),
                    transcript
                )
            }
        }
        let intent = try await HuggingFaceGemmaIntentService.parseIntent(
            transcript: transcript,
            endpoint: endpoint,
            accessToken: hfToken,
            uiTripContext: uiTripContext,
            facilityCatalogBlock: facilityCatalogBlock
        )
        return (intent, transcript)
    }

    private func parseIntentFromText(
        _ prompt: String,
        uiTripContext: String?,
        attachmentJPEG: Data? = nil,
        facilityCatalogBlock: String
    ) async throws -> BookingIntent {
        let hfToken = ResolvedLLMKeys.huggingFaceAccessToken
        guard hfToken.isEmpty == false else {
            throw missingAPIKeysError()
        }
        guard let endpoint = URL(string: Secrets.huggingFaceGemmaEndpoint) else {
            throw NSError(domain: "Innsy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Secrets.huggingFaceGemmaEndpoint URL."])
        }
        let hasImage = attachmentJPEG.map { !$0.isEmpty } ?? false

        if hasImage, let jpeg = attachmentJPEG {
            return try await HuggingFaceGemmaIntentService.parseIntentMultimodal(
                userText: prompt,
                jpegData: jpeg,
                endpoint: endpoint,
                accessToken: hfToken,
                uiTripContext: uiTripContext,
                facilityCatalogBlock: facilityCatalogBlock
            )
        }
        return try await HuggingFaceGemmaIntentService.parseIntent(
            transcript: prompt,
            endpoint: endpoint,
            accessToken: hfToken,
            uiTripContext: uiTripContext,
            facilityCatalogBlock: facilityCatalogBlock
        )
    }

    private func runHotelFetchPipeline(
        parsed incoming: BookingIntent,
        facilityMatchText: String? = nil,
        activeGeneration gen: UInt64
    ) async throws {
        try throwIfSearchStale(gen)
        var parsed = incoming
        await FacilityCodebookStore.shared.preloadIfNeeded(using: pipeline)
        let codebookMap = await FacilityCodebookStore.shared.cachedFacilityNamesByCode()
        try throwIfSearchStale(gen)
        let validFacilityCodes = Set(codebookMap.keys)
        let allowlistCodes = GemmaFacilityAllowlist.allowedCodes()
        if validFacilityCodes.isEmpty == false {
            parsed.facilityCodes = parsed.facilityCodes.filter { validFacilityCodes.contains($0) }
        }
        if allowlistCodes.isEmpty == false {
            parsed.facilityCodes = parsed.facilityCodes.filter { allowlistCodes.contains($0) }
        }

        try throwIfSearchStale(gen)
        emptyResultsExplanation = nil
        let allowNames = GemmaFacilityAllowlist.namesByCode()
        var displayNames: [Int: String] = [:]
        displayNames.reserveCapacity(parsed.facilityCodes.count)
        for code in parsed.facilityCodes {
            if let label = codebookMap[code] ?? allowNames[code], label.isEmpty == false {
                displayNames[code] = label
            } else {
                displayNames[code] = "Facility \(code)"
            }
        }
        try throwIfSearchStale(gen)
        intentFacilityDisplayNamesByCode = displayNames
        intent = parsed
        try throwIfSearchStale(gen)

        guard parsed.checkIn.isEmpty == false, parsed.checkOut.isEmpty == false else {
            throw NSError(
                domain: "Innsy",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Check-in and check-out dates are required in YYYY-MM-DD format."]
            )
        }

        guard let dest = HotelbedsDestinationResolver.resolveCode(for: parsed) else {
            throw NSError(
                domain: "Innsy",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not resolve an HBX destination code. Say a city (e.g. Paris) — not a country code. Paris maps to PAR, not FR."]
            )
        }

        try throwIfSearchStale(gen)

        phase = .fetchingHotels

        async let contentTask = pipeline.fetchHotelContent(
            destinationCode: dest,
            countryCode: parsed.countryCode?.uppercased(),
            limit: 120
        )
        let content = try await contentTask
        try throwIfSearchStale(gen)
        let codes = content.map(\.code)
        guard codes.isEmpty == false else {
            throw NSError(
                domain: "Innsy",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "No hotels in Content API for code \(dest). If the city is correct (e.g. PAR for Paris), your test key may have a limited portfolio — see https://developer.hotelbeds.com/documentation/getting-started/"]
            )
        }

        let availability = try await pipeline.fetchAvailability(intent: parsed, hotelCodes: codes)
        try throwIfSearchStale(gen)
        let facilityNamesByCode = await FacilityCodebookStore.shared.cachedFacilityNamesByCode()
        // Match spoken/written amenities with the same code→label map the model sees when allowlist is active.
        let transcriptCodebook: [Int: String] = allowlistCodes.isEmpty
            ? facilityNamesByCode
            : GemmaFacilityAllowlist.namesByCode()
        var fromTranscript = Self.facilityCodesMatchingUserText(facilityMatchText, codebook: transcriptCodebook)
        if allowlistCodes.isEmpty == false {
            fromTranscript = fromTranscript.filter { allowlistCodes.contains($0) }
        }
        let fromModel = parsed.facilityCodes
        let requiredFacilityCodes = Array(Set(fromTranscript + fromModel)).sorted()
        var map: [Int: HotelContentHotel] = [:]
        for h in content { map[h.code] = h }

        var merged = HotelOfferCard.merge(
            availability: availability,
            contentByCode: map,
            intent: parsed,
            requestedFacilityCodes: requiredFacilityCodes,
            facilityNamesByCode: facilityNamesByCode
        )
        try throwIfSearchStale(gen)
        cards = merged
        try throwIfSearchStale(gen)
        phase = .ready
        if cards.isEmpty {
            let msg = """
            No hotels to list: Hotelbeds returned no rates in your price range for these dates and hotels, or no availability matched the stay. Try widening dates or budget.
            """
            alertMessage = msg
            emptyResultsExplanation = msg
        }
    }

    private static func facilityCodesMatchingUserText(_ text: String?, codebook: [Int: String]) -> [Int] {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return [] }
        return FacilityCodeMatcher.facilityCodesMentioned(in: trimmed, namesByCode: codebook)
    }

    private func missingAPIKeysError() -> NSError {
        NSError(
            domain: "Innsy",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: """
            Gemma runs on Hugging Face Inference. You need a Hugging Face access token (not the endpoint URL).

            • Create a token at https://huggingface.co/settings/tokens
            • Paste it in the app or set huggingFaceAccessToken in Secrets.swift (starts with hf_).
            • Set huggingFaceGemmaEndpoint in Secrets.swift to your Inference Endpoint URL.
            """]
        )
    }

    func fetchRoomImageMap(for hotelCode: Int) async -> HotelbedsHotelPipeline.RoomImageMap {
        do {
            return try await pipeline.fetchRoomImageMap(hotelCode: hotelCode)
        } catch {
            return .init(byRoomCode: [:], byRoomName: [:])
        }
    }

    private static func describe(error: Error) -> String {
        if let de = error as? DecodingError {
            return "JSON decoding failed: \(Self.formatDecodingError(de)). Raw API shapes sometimes differ in test vs production."
        }
        return error.localizedDescription
    }

    private static func formatDecodingError(_ e: DecodingError) -> String {
        switch e {
        case let .keyNotFound(key, ctx):
            "missing key \"\(key.stringValue)\" at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case let .typeMismatch(type, ctx):
            "type \(type) mismatch at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case let .valueNotFound(type, ctx):
            "missing \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case let .dataCorrupted(ctx):
            ctx.debugDescription
        @unknown default:
            String(describing: e)
        }
    }

    func confirmBooking(
        card: HotelOfferCard,
        selectedRateKey: String? = nil,
        selectedRateType: String? = nil,
        holderGiven: String,
        holderFamily: String,
        guestGiven: String,
        guestFamily: String
    ) async -> Bool {
        phase = .booking
        defer { phase = .ready }
        do {
            var rateKey = selectedRateKey ?? card.rateKey
            let rateType = selectedRateType ?? card.rateType
            if rateType == "RECHECK" {
                rateKey = try await pipeline.recheck(rateKey: rateKey)
            }

            let ref = "Innsy-\(Int(Date().timeIntervalSince1970))"
            let response = try await pipeline.createBooking(
                rateKey: rateKey,
                holderGiven: holderGiven,
                holderFamily: holderFamily,
                guestGiven: guestGiven,
                guestFamily: guestFamily,
                adults: intent?.adults ?? 2,
                clientReference: ref
            )
            lastBookingReference = response.booking?.reference ?? ref
            return true
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }
}
