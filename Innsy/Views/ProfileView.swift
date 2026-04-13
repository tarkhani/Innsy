//
//  ProfileView.swift
//  Innsy
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: UserSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var reservationToCancel: UserSessionViewModel.ReservationRecord?

    var body: some View {
        NavigationStack {
            List {
                if let user = session.currentUser {
                    Section("Account") {
                        LabeledContent("Name", value: user.fullName)
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Auth method", value: user.authMethod == .google ? "Google" : "Email/Password")
                    }
                }

                Section("Reservations") {
                    if session.reservations.isEmpty {
                        Text("No reservations yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.reservations) { reservation in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reservation.hotelName)
                                        .font(.headline)
                                    Text("Code: \(reservation.bookingReference)")
                                        .font(.system(.subheadline, design: .monospaced))
                                    Text(reservation.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Button("Cancel", role: .destructive) {
                                    reservationToCancel = reservation
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Cancel this reservation?",
                isPresented: Binding(
                    get: { reservationToCancel != nil },
                    set: { if $0 == false { reservationToCancel = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Cancel reservation", role: .destructive) {
                    guard let reservation = reservationToCancel else { return }
                    session.cancelReservation(id: reservation.id)
                    reservationToCancel = nil
                }
                Button("Keep", role: .cancel) {
                    reservationToCancel = nil
                }
            } message: {
                if let reservation = reservationToCancel {
                    Text("This will remove reservation \(reservation.bookingReference) from your profile.")
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .foregroundStyle(.orange)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        session.logout()
                        dismiss()
                    } label: {
                        Text("Logout")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .tint(.orange)
    }
}
