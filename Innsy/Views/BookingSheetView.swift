//
//  BookingSheetView.swift
//  Innsy
//

import SwiftUI

struct BookingSheetView: View {
    private struct RoomRateOption: Identifiable, Hashable {
        let id: String
        let roomName: String
        let roomCode: String
        let rateKey: String
        let rateType: String?
        let boardName: String?
        let price: String?
        let allotment: Int?
        let cancellationPolicy: String?
    }

    let card: HotelOfferCard
    @ObservedObject var viewModel: HotelBookingViewModel
    var onBooked: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var holderGiven = "Alex"
    @State private var holderFamily = "Traveler"
    @State private var guestGiven = "Alex"
    @State private var guestFamily = "Traveler"
    @State private var isSubmitting = false
    @State private var confirmedReference: String?
    @State private var showReservationSheet = false
    @State private var selectedOptionID: String?
    @State private var roomImagesByCode: [String: [URL]] = [:]
    @State private var roomImagesByName: [String: [URL]] = [:]
    @State private var isLoadingRoomImages = false

    var body: some View {
        NavigationStack {
            Form {
                if roomOptions.isEmpty == false {
                    Section("Room options") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(galleryImageURLs, id: \.absoluteString) { url in
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        default:
                                            Color.gray.opacity(0.15)
                                        }
                                    }
                                    .frame(width: 180, height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                        if isLoadingRoomImages {
                            ProgressView("Loading room images...")
                                .font(.caption)
                        }

                        ForEach(roomOptions) { option in
                            Button {
                                selectedOptionID = option.id
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: selectedOptionID == option.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedOptionID == option.id ? .orange : .secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.roomName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text("Code: \(option.roomCode)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let board = option.boardName, board.isEmpty == false {
                                            Text(board)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let type = option.rateType {
                                            Text(type == "RECHECK" ? "Requires re-check before booking" : "Ready to book")
                                                .font(.caption2)
                                                .foregroundStyle(type == "RECHECK" ? .orange : .green)
                                        }
                                        if let policy = option.cancellationPolicy, policy.isEmpty == false {
                                            Text(policy)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    if let cur = card.currency, let price = option.price, price.isEmpty == false {
                                        Text("\(cur) \(price)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Lead guest") {
                    TextField("Given name", text: $holderGiven)
                    TextField("Surname", text: $holderFamily)
                }
                Section("Room guests") {
                    TextField("Primary guest given name", text: $guestGiven)
                    TextField("Primary guest surname", text: $guestFamily)
                }
                Section("Selection") {
                    Text(card.name).font(.headline)
                    if let selected = selectedOption {
                        if let price = selected.price, let cur = card.currency {
                            Text("\(cur) \(price)")
                        }
                        Text(selected.roomName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if let price = card.fromPrice, let cur = card.currency {
                        Text("\(cur) \(price)")
                    }
                }
                if let ref = confirmedReference {
                    Section("Confirmation") {
                        Text("Reference: \(ref)")
                            .font(.body.monospaced())
                    }
                }
            }
            .navigationTitle("Booking")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Book") {
                        Task { await submit() }
                    }
                    .disabled(
                        isSubmitting
                            || holderGiven.isEmpty
                            || holderFamily.isEmpty
                            || selectedRateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .sheet(isPresented: $showReservationSheet) {
            if let selected = selectedOption {
                ReservationConfirmationSheet(
                    hotelName: card.name,
                    peopleCount: (viewModel.intent?.adults ?? 0) + (viewModel.intent?.children ?? 0),
                    totalAmount: amountLine(for: selected),
                    cancellationPolicy: selected.cancellationPolicy ?? "Cancellation policy was not provided for this rate.",
                    referenceCode: confirmedReference ?? "UNKNOWN"
                )
            }
        }
        .onAppear {
            if selectedOptionID == nil {
                selectedOptionID = roomOptions.first?.id
            }
        }
        .task {
            await loadRoomImages()
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let ok = await viewModel.confirmBooking(
            card: card,
            selectedRateKey: selectedRateKey,
            selectedRateType: selectedOption?.rateType,
            holderGiven: holderGiven,
            holderFamily: holderFamily,
            guestGiven: guestGiven,
            guestFamily: guestFamily
        )
        if ok {
            let reference = viewModel.lastBookingReference ?? "UNKNOWN"
            confirmedReference = reference
            showReservationSheet = true
            onBooked?(reference)
        }
    }

    private var roomOptions: [RoomRateOption] {
        guard let rooms = card.availabilityHotel.rooms else { return [] }
        var options: [RoomRateOption] = []

        for (roomIndex, room) in rooms.enumerated() {
            guard let rates = room.rates else { continue }
            for (rateIndex, rate) in rates.enumerated() {
                guard let key = rate.rateKey, key.isEmpty == false else { continue }
                let id = "\(roomIndex)-\(rateIndex)-\(key)"
                options.append(
                    RoomRateOption(
                        id: id,
                        roomName: room.name ?? "Room",
                        roomCode: room.code ?? "-",
                        rateKey: key,
                        rateType: rate.rateType,
                        boardName: rate.boardName,
                        price: rate.sellingRate ?? rate.net,
                        allotment: rate.allotment,
                        cancellationPolicy: cancellationPolicyText(for: rate)
                    )
                )
            }
        }

        return options.sorted { lhs, rhs in
            func rank(_ t: String?) -> Int {
                switch t {
                case "BOOKABLE": return 0
                case "RECHECK": return 1
                default: return 2
                }
            }
            if rank(lhs.rateType) != rank(rhs.rateType) {
                return rank(lhs.rateType) < rank(rhs.rateType)
            }
            let lp = numericPrice(lhs.price)
            let rp = numericPrice(rhs.price)
            return lp < rp
        }
    }

    private var selectedOption: RoomRateOption? {
        guard let selectedOptionID else { return roomOptions.first }
        return roomOptions.first(where: { $0.id == selectedOptionID }) ?? roomOptions.first
    }

    private var selectedRateKey: String {
        selectedOption?.rateKey ?? card.rateKey
    }

    private var galleryImageURLs: [URL] {
        if let selected = selectedOption,
           let content = card.contentHotel,
           let selectedRoomKey = normalizedRoomKey(selected.roomCode) {
            let matchedRoomImages: [HotelContentHotel.HotelImage] = (content.images ?? [])
                .filter { image in
                    guard image.imageTypeCode?.uppercased() == "HAB",
                          let imageRoomKey = normalizedRoomKey(image.roomCode) else {
                        return false
                    }
                    return isSameRoom(selected: selectedRoomKey, imageRoomCode: imageRoomKey)
                }
                .sorted { a, b in
                    let av = a.visualOrder ?? Int.max
                    let bv = b.visualOrder ?? Int.max
                    if av != bv { return av < bv }
                    return (a.order ?? 0) < (b.order ?? 0)
                }
            let roomSpecific: [URL] = matchedRoomImages.compactMap { img -> URL? in
                guard let path = img.path else { return nil }
                return HotelContentHotel.hotelbedsPhotoURL(relativePath: path, size: .bigger)
            }

            if roomSpecific.isEmpty == false {
                return Array(roomSpecific.prefix(6))
            }
        }

        if let selected = selectedOption {
            let codeKey = normalizedRoomKey(selected.roomCode)
            if let codeKey, let list = roomImagesByCode[codeKey], list.isEmpty == false {
                return Array(list.prefix(6))
            }
            let nameKey = normalizedRoomKey(selected.roomName)
            if let nameKey, let list = roomImagesByName[nameKey], list.isEmpty == false {
                return Array(list.prefix(6))
            }
        }

        guard let content = card.contentHotel else { return [] }
        let sortedImages = (content.images ?? []).sorted { a, b in
            score(for: a.imageTypeCode) < score(for: b.imageTypeCode)
        }
        let topImages = Array(sortedImages.prefix(6))
        let roomFirst: [URL] = topImages.compactMap { img -> URL? in
            guard let path = img.path else { return nil }
            return HotelContentHotel.hotelbedsPhotoURL(relativePath: path, size: .bigger)
        }

        if roomFirst.isEmpty, let single = content.primaryImageURL {
            return [single]
        }
        return roomFirst
    }

    private func isSameRoom(selected: String, imageRoomCode: String) -> Bool {
        if selected == imageRoomCode { return true }
        let selectedPrefix = selected.split(separator: ".").first.map(String.init) ?? selected
        let imagePrefix = imageRoomCode.split(separator: ".").first.map(String.init) ?? imageRoomCode
        return selectedPrefix == imagePrefix
    }

    private func loadRoomImages() async {
        guard roomImagesByCode.isEmpty, roomImagesByName.isEmpty else { return }
        isLoadingRoomImages = true
        defer { isLoadingRoomImages = false }
        let roomMap = await viewModel.fetchRoomImageMap(for: card.hotelCode)
        roomImagesByCode = roomMap.byRoomCode
        roomImagesByName = roomMap.byRoomName
    }

    private func normalizedRoomKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.isEmpty ? nil : key
    }

    private func score(for imageTypeCode: String?) -> Int {
        switch imageTypeCode?.uppercased() {
        case "HAB": return 0
        case "GEN", "COM": return 1
        default: return 2
        }
    }

    private func numericPrice(_ value: String?) -> Double {
        guard let value else { return .greatestFiniteMagnitude }
        let filtered = value.filter { "0123456789.".contains($0) }
        return Double(filtered) ?? .greatestFiniteMagnitude
    }

    private func amountLine(for option: RoomRateOption) -> String {
        let currency = card.currency ?? ""
        let price = option.price ?? card.fromPrice ?? "-"
        if currency.isEmpty { return price }
        return "\(currency) \(price)"
    }

    private func cancellationPolicyText(for rate: AvailabilityHotel.AvailabilityRate) -> String? {
        guard let first = rate.cancellationPolicies?.first else { return nil }
        let amount = first.amount?.trimmingCharacters(in: .whitespacesAndNewlines)
        let from = first.from?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let from, from.isEmpty == false, let amount, amount.isEmpty == false {
            let currency = card.currency ?? ""
            let amountLine = currency.isEmpty ? amount : "\(currency) \(amount)"
            return "Free cancellation before \(from). Penalty after: \(amountLine)."
        }
        if let from, from.isEmpty == false {
            return "Free cancellation before \(from)."
        }
        if let amount, amount.isEmpty == false {
            let currency = card.currency ?? ""
            return currency.isEmpty ? "Penalty on cancellation: \(amount)." : "Penalty on cancellation: \(currency) \(amount)."
        }
        return nil
    }
}

private struct ReservationConfirmationSheet: View {
    let hotelName: String
    let peopleCount: Int
    let totalAmount: String
    let cancellationPolicy: String
    let referenceCode: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Reservation complete") {
                    Text(hotelName)
                        .font(.headline)
                }

                Section("Details") {
                    LabeledContent("People", value: "\(max(peopleCount, 1))")
                    LabeledContent("Total amount", value: totalAmount)
                    LabeledContent("Reference code") {
                        Text(referenceCode)
                            .font(.body.monospaced())
                    }
                }

                Section("Cancellation policy") {
                    Text(cancellationPolicy)
                        .font(.subheadline)
                }
            }
            .navigationTitle("Reservation info")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
