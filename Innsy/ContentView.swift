//
//  ContentView.swift
//  Innsy
//
//  Created by Ahmadreza Tarkhani on 09/04/2026.
//

import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    private enum ResultsDestination: Hashable {
        case results
    }

    @StateObject private var viewModel = HotelBookingViewModel()
    @State private var navigationPath = NavigationPath()
    @EnvironmentObject private var session: UserSessionViewModel
    @State private var bookingCard: HotelOfferCard?
    @State private var pendingBookingCard: HotelOfferCard?
    @State private var showAuthSheet = false
    @State private var showProfileSheet = false
    @State private var heroImageIndex = 0
    @State private var promptText = ""
    @State private var promptAttachmentItem: PhotosPickerItem?
    @State private var promptAttachmentJPEG: Data?
    private let heroImageURLs: [String] = [
        "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=1600&q=80",
        "https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=1600&q=80",
        "https://images.unsplash.com/photo-1501785888041-af3ef285b470?auto=format&fit=crop&w=1600&q=80",
        "https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?auto=format&fit=crop&w=1600&q=80",
    ]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                heroBackground
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.48),
                        Color.black.opacity(0.62),
                        Color(red: 0.06, green: 0.06, blue: 0.08),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ZStack {
                    VStack(spacing: 16) {
                        mainHeadline
                        voiceActionCard
                    }
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tint(Color.orange)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationDestination(for: ResultsDestination.self) { _ in
                HotelSearchResultsView(viewModel: viewModel) { card in
                    if session.isLoggedIn {
                        bookingCard = card
                    } else {
                        pendingBookingCard = card
                        showAuthSheet = true
                    }
                }
                .environmentObject(session)
            }
            .onChange(of: viewModel.phase) { _, phase in
                guard phase == .parsingAudio || phase == .fetchingHotels else { return }
                if navigationPath.isEmpty {
                    navigationPath.append(ResultsDestination.results)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    InnsyNavigationTitle()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if session.isLoggedIn {
                            showProfileSheet = true
                        } else {
                            showAuthSheet = true
                        }
                    } label: {
                        Image(systemName: session.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
                            .foregroundStyle(.orange)
                    }
                    .accessibilityLabel(session.isLoggedIn ? "Open profile" : "Login")
                }
            }
            .alert("Notice", isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.alertMessage = nil }
            } message: {
                Text(viewModel.alertMessage ?? "")
            }
            .sheet(item: $bookingCard) { card in
                BookingSheetView(card: card, viewModel: viewModel) { reference in
                    session.addReservation(reference: reference, hotelName: card.name)
                }
            }
            .sheet(isPresented: $showAuthSheet, onDismiss: {
                if session.isLoggedIn, let queued = pendingBookingCard {
                    bookingCard = queued
                }
                pendingBookingCard = nil
            }) {
                AuthSheetView()
                    .environmentObject(session)
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView()
                    .environmentObject(session)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var mainHeadline: some View {
        Text("Describe your dream stay.")
            .font(.title2.weight(.bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 2)
    }

    private var heroBackground: some View {
        AsyncImage(url: URL(string: heroImageURLs[heroImageIndex])) { phase in
            Group {
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    LinearGradient(
                        colors: [Color.black, Color(red: 0.22, green: 0.16, blue: 0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .animation(.easeInOut(duration: 0.8), value: heroImageIndex)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
        .onReceive(Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.8)) {
                heroImageIndex = (heroImageIndex + 1) % heroImageURLs.count
            }
        }
    }

    private var voiceActionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "",
                text: $promptText,
                prompt: Text("Type your dream stay and tap to speak")
                    .foregroundStyle(Color(red: 0.32, green: 0.32, blue: 0.34)),
                axis: .vertical
            )
                .lineLimit(3, reservesSpace: true)
                .font(.subheadline)
                .foregroundStyle(.black)
                .tint(Color.orange)

            if let attachmentData = promptAttachmentJPEG, let ui = UIImage(data: attachmentData) {
                HStack(spacing: 10) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer(minLength: 0)
                    Button("Remove") {
                        promptAttachmentItem = nil
                        promptAttachmentJPEG = nil
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                }
                .padding(10)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Upload a photo of the view you like.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                PhotosPicker(selection: $promptAttachmentItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(Color.orange)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .onChange(of: promptAttachmentItem) { _, newItem in
                    Task { await loadPromptAttachment(from: newItem) }
                }

                Button {
                    Task { await viewModel.recordTap(attachmentJPEG: promptAttachmentJPEG, tripContext: tripSnapshot()) }
                } label: {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.title3)
                        .foregroundStyle(viewModel.isRecording ? .red : Color.orange)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.06), in: Circle())
                }

                Button {
                    Task {
                        let jpeg = promptAttachmentJPEG
                        await viewModel.submitTextPrompt(
                            promptText,
                            attachmentJPEG: jpeg,
                            tripContext: tripSnapshot()
                        )
                        if viewModel.phase == .ready {
                            promptAttachmentJPEG = nil
                            promptAttachmentItem = nil
                        }
                    }
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityLabel("Send")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(0.9), lineWidth: 2)
        }
    }

    @MainActor
    private func loadPromptAttachment(from item: PhotosPickerItem?) async {
        guard let item else {
            promptAttachmentJPEG = nil
            return
        }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                promptAttachmentJPEG = nil
                viewModel.alertMessage = "Could not read photo data."
                return
            }
            guard let ui = UIImage(data: raw) else {
                promptAttachmentJPEG = nil
                viewModel.alertMessage = "Could not open image."
                return
            }
            guard let jpeg = InferenceJPEG.dataForModel(from: ui) else {
                promptAttachmentJPEG = nil
                viewModel.alertMessage = "Could not prepare image for the model."
                return
            }
            promptAttachmentJPEG = jpeg
        } catch {
            promptAttachmentJPEG = nil
            viewModel.alertMessage = error.localizedDescription
        }
    }

    private func tripSnapshot() -> TripPromptContext {
        let today = Date()
        let defaultCheckout = Calendar.current.date(byAdding: .day, value: 2, to: today) ?? today
        return TripPromptContext(
            checkIn: today,
            checkOut: defaultCheckout,
            guests: 1,
            minBudget: "",
            maxBudget: ""
        )
    }
}

// MARK: - Branded navigation title

private struct InnsyNavigationTitle: View {
    @State private var breathe = false

    var body: some View {
        ZStack {
            Text("Innsy")
                .font(.system(size: 26, weight: .ultraLight, design: .rounded))
                .tracking(6)
                .blur(radius: breathe ? 11 : 5)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.9), Color.orange.opacity(0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(y: 1)

            Text("Innsy")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .tracking(6)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 1, green: 0.93, blue: 0.82),
                            Color(red: 1, green: 0.62, blue: 0.28),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 2)
                .shadow(color: .orange.opacity(breathe ? 0.9 : 0.45), radius: breathe ? 16 : 9, x: 0, y: 0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .accessibilityLabel("Innsy")
    }
}

#Preview {
    ContentView()
}
