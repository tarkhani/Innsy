//
//  UserSessionViewModel.swift
//  Innsy
//

import Foundation

@MainActor
final class UserSessionViewModel: ObservableObject {
    enum AuthMethod: String, Codable, Equatable {
        case manual
        case google
    }

    struct UserAccount: Codable, Equatable {
        let email: String
        var fullName: String
        var password: String?
        var authMethod: AuthMethod
    }

    struct ReservationRecord: Codable, Identifiable, Equatable {
        let id: UUID
        let bookingReference: String
        let hotelName: String
        let createdAt: Date
    }

    @Published private(set) var currentUser: UserAccount?
    @Published private(set) var reservations: [ReservationRecord] = []
    @Published var authErrorMessage: String?

    var isLoggedIn: Bool { currentUser != nil }

    private var usersByEmail: [String: UserAccount] = [:]
    private var reservationsByEmail: [String: [ReservationRecord]] = [:]

    private let usersKey = "Innsy.usersByEmail"
    private let reservationsKey = "Innsy.reservationsByEmail"
    private let currentUserKey = "Innsy.currentUserEmail"

    init() {
        loadFromStorage()
    }

    func register(fullName: String, email: String, password: String) -> Bool {
        let normalizedEmail = normalized(email)
        guard normalizedEmail.isEmpty == false else {
            authErrorMessage = "Email is required."
            return false
        }
        let failures = passwordValidationFailures(password: password, email: normalizedEmail)
        guard failures.isEmpty else {
            authErrorMessage = failures.joined(separator: "\n")
            return false
        }
        guard usersByEmail[normalizedEmail] == nil else {
            authErrorMessage = "An account with this email already exists."
            return false
        }

        let safeName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = UserAccount(
            email: normalizedEmail,
            fullName: safeName.isEmpty ? "Traveler" : safeName,
            password: password,
            authMethod: .manual
        )
        usersByEmail[normalizedEmail] = account
        currentUser = account
        reservations = reservationsByEmail[normalizedEmail] ?? []
        authErrorMessage = nil
        persist()
        return true
    }

    func login(email: String, password: String) -> Bool {
        let normalizedEmail = normalized(email)
        guard let account = usersByEmail[normalizedEmail] else {
            authErrorMessage = "No account found for this email."
            return false
        }
        guard account.authMethod == .manual else {
            authErrorMessage = "This account uses Google sign-in. Use Continue with Google."
            return false
        }
        guard account.password == password else {
            authErrorMessage = "Incorrect password."
            return false
        }
        currentUser = account
        reservations = reservationsByEmail[normalizedEmail] ?? []
        authErrorMessage = nil
        persist()
        return true
    }

    /// Call after Google OAuth succeeds (verified email from `GIDGoogleUser`).
    func signInOrRegisterWithGoogle(email: String, displayName: String?) -> Bool {
        let normalizedEmail = normalized(email)
        guard normalizedEmail.isEmpty == false else {
            authErrorMessage = "Google did not provide a valid email."
            return false
        }

        if let existing = usersByEmail[normalizedEmail] {
            guard existing.authMethod == .google else {
                authErrorMessage = "This email is registered with a password. Sign in with email instead."
                return false
            }
            var updated = existing
            if let displayName, displayName.isEmpty == false {
                updated.fullName = displayName
            }
            usersByEmail[normalizedEmail] = updated
            currentUser = updated
            reservations = reservationsByEmail[normalizedEmail] ?? []
            authErrorMessage = nil
            persist()
            return true
        }

        let safeName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackName = normalizedEmail.split(separator: "@").first.map(String.init) ?? "Traveler"
        let account = UserAccount(
            email: normalizedEmail,
            fullName: safeName.isEmpty ? fallbackName : safeName,
            password: nil,
            authMethod: .google
        )
        usersByEmail[normalizedEmail] = account
        currentUser = account
        reservations = reservationsByEmail[normalizedEmail] ?? []
        authErrorMessage = nil
        persist()
        return true
    }

    func logout() {
        GoogleSignInManager.signOut()
        currentUser = nil
        reservations = []
        authErrorMessage = nil
        persist()
    }

    func addReservation(reference: String, hotelName: String) {
        guard let email = currentUser?.email else { return }
        let entry = ReservationRecord(
            id: UUID(),
            bookingReference: reference,
            hotelName: hotelName,
            createdAt: Date()
        )
        var list = reservationsByEmail[email] ?? []
        list.insert(entry, at: 0)
        reservationsByEmail[email] = list
        reservations = list
        persist()
    }

    func cancelReservation(id: ReservationRecord.ID) {
        guard let email = currentUser?.email else { return }
        var list = reservationsByEmail[email] ?? []
        list.removeAll { $0.id == id }
        reservationsByEmail[email] = list
        reservations = list
        persist()
    }

    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func passwordValidationFailures(password: String, email: String) -> [String] {
        var issues: [String] = []
        if password.count < 12 {
            issues.append("Password must be at least 12 characters.")
        }
        if password.rangeOfCharacter(from: .uppercaseLetters) == nil {
            issues.append("Include at least one uppercase letter.")
        }
        if password.rangeOfCharacter(from: .lowercaseLetters) == nil {
            issues.append("Include at least one lowercase letter.")
        }
        if password.rangeOfCharacter(from: .decimalDigits) == nil {
            issues.append("Include at least one number.")
        }
        let symbols = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:'\",.<>?/`~\\")
        if password.rangeOfCharacter(from: symbols) == nil {
            issues.append("Include at least one special character.")
        }
        if password.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            issues.append("Password cannot contain spaces.")
        }
        let lowered = password.lowercased()
        let forbidden = ["password", "123456", "qwerty", "letmein", "admin"]
        if forbidden.contains(where: { lowered.contains($0) }) {
            issues.append("Avoid common/guessable words or sequences.")
        }
        let emailPrefix = email.split(separator: "@").first.map(String.init) ?? ""
        if emailPrefix.isEmpty == false, lowered.contains(emailPrefix.lowercased()) {
            issues.append("Password should not include your email name.")
        }
        return issues
    }

    private func loadFromStorage() {
        let defaults = UserDefaults.standard
        if let usersData = defaults.data(forKey: usersKey),
           let decodedUsers = try? JSONDecoder().decode([String: UserAccount].self, from: usersData) {
            usersByEmail = decodedUsers
        }
        if let reservationData = defaults.data(forKey: reservationsKey),
           let decodedReservations = try? JSONDecoder().decode([String: [ReservationRecord]].self, from: reservationData) {
            reservationsByEmail = decodedReservations
        }

        if let savedEmail = defaults.string(forKey: currentUserKey),
           let user = usersByEmail[savedEmail] {
            currentUser = user
            reservations = reservationsByEmail[savedEmail] ?? []
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let usersData = try? JSONEncoder().encode(usersByEmail) {
            defaults.set(usersData, forKey: usersKey)
        }
        if let reservationData = try? JSONEncoder().encode(reservationsByEmail) {
            defaults.set(reservationData, forKey: reservationsKey)
        }
        defaults.set(currentUser?.email, forKey: currentUserKey)
    }
}
