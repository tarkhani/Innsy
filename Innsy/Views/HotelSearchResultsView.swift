//
//  HotelSearchResultsView.swift
//  Innsy
//

import SwiftUI

struct HotelSearchResultsView: View {
    @ObservedObject var viewModel: HotelBookingViewModel
    @EnvironmentObject private var session: UserSessionViewModel
    var onRequestBook: (HotelOfferCard) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let intent = viewModel.intent {
                    tripSummary(intent: intent)
                }
                if viewModel.phase == .parsingAudio || viewModel.phase == .fetchingHotels {
                    ProgressView("Finding the best hotel for you")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                if viewModel.phase == .ready, viewModel.cards.isEmpty, viewModel.intent != nil,
                   let hint = viewModel.emptyResultsExplanation?.trimmingCharacters(in: .whitespacesAndNewlines),
                   hint.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No hotels to show")
                            .font(.subheadline.weight(.semibold))
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                ForEach(viewModel.cards) { card in
                    HotelCardView(
                        card: card,
                        onBook: { onRequestBook(card) },
                        ctaTitle: session.isLoggedIn ? "Continue to booking" : "Login to book"
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.08, blue: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Matches")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.orange)
        .onDisappear {
            if viewModel.phase == .parsingAudio || viewModel.phase == .fetchingHotels {
                viewModel.cancelSearchBecauseUserNavigatedBack()
            }
        }
    }

    private func tripSummary(intent: BookingIntent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your trip")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(intent.checkIn) → \(intent.checkOut)")
                .font(.subheadline.weight(.semibold))
            Text(
                [
                    intent.destinationName,
                    intent.hotelbedsDestinationCode.map { "Code \($0)" },
                    intent.countryCode.map { "Country \($0)" },
                ]
                .compactMap { $0 }
                .joined(separator: " · ")
            )
            .font(.footnote)
            Text("\(intent.rooms) room(s), \(intent.adults) adults, \(intent.children) children")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let budgetLine = budgetLine(for: intent) {
                Text("Budget: \(budgetLine)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if intent.preferences.isEmpty == false {
                Text("Preferences: \(intent.preferences.joined(separator: ", "))")
                    .font(.footnote)
            }
            if intent.facilityCodes.isEmpty == false {
                let labels = intent.facilityCodes.map { code in
                    viewModel.intentFacilityDisplayNamesByCode[code] ?? "Facility \(code)"
                }
                Text("Amenities that we think you're interested in: \(labels.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let expl = intent.gemmaInferenceExplanation?.trimmingCharacters(in: .whitespacesAndNewlines), expl.isEmpty == false {
                Divider()
                    .opacity(0.45)
                Text("What the model inferred")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(expl)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func budgetLine(for intent: BookingIntent) -> String? {
        guard intent.minPrice != nil || intent.maxPrice != nil else { return nil }
        let minText = intent.minPrice.map { String(format: "%.0f", $0) }
        let maxText = intent.maxPrice.map { String(format: "%.0f", $0) }
        let budgetText: String
        switch (minText, maxText) {
        case let (min?, max?):
            budgetText = "\(min) - \(max)"
        case let (min?, nil):
            budgetText = ">= \(min)"
        case let (nil, max?):
            budgetText = "<= \(max)"
        default:
            budgetText = "-"
        }
        let currency = intent.currency?.uppercased()
        let prefix = (currency?.isEmpty == false) ? "\(currency!) " : ""
        return "\(prefix)\(budgetText)"
    }
}
