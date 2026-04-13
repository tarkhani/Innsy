//
//  AuthSheetView.swift
//  Innsy
//

import SwiftUI

struct AuthSheetView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case login = "Login"
        case register = "Register"

        var id: String { rawValue }
    }

    @EnvironmentObject private var session: UserSessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .login
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isGoogleSigningIn = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.08, green: 0.08, blue: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        emailFormSection
                        socialDivider
                        googleButton
                        modeSwitcher
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func submitEmail() {
        session.authErrorMessage = nil
        let ok: Bool
        switch mode {
        case .login:
            ok = session.login(email: email, password: password)
        case .register:
            guard password == confirmPassword else {
                session.authErrorMessage = "Passwords do not match."
                return
            }
            ok = session.register(fullName: fullName, email: email, password: password)
        }
        if ok { dismiss() }
    }

    private func startGoogleSignIn() {
        Task {
            session.authErrorMessage = nil
            isGoogleSigningIn = true
            defer { isGoogleSigningIn = false }

            guard let presenter = GoogleSignInManager.topViewController() else {
                session.authErrorMessage = "Could not open Google sign-in."
                return
            }
            do {
                let result = try await GoogleSignInManager.signIn(presenting: presenter)
                let ok = session.signInOrRegisterWithGoogle(
                    email: result.email,
                    displayName: result.displayName
                )
                if ok { dismiss() }
            } catch {
                if GoogleSignInManager.isUserCanceledSignIn(error) {
                    return
                }
                session.authErrorMessage = error.localizedDescription
            }
        }
    }

    private var primaryButtonTitle: String {
        mode == .login ? "Sign in" : "Create account"
    }

    private var isEmailSubmitDisabled: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .register {
            return trimmedEmail.isEmpty || password.isEmpty || confirmPassword.isEmpty || fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return trimmedEmail.isEmpty || password.isEmpty
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Innsy")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange, Color(red: 1.0, green: 0.55, blue: 0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text(mode == .login ? "Welcome back" : "Create an account to continue")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var emailFormSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if mode == .register {
                inputField("Full name", text: $fullName)
            }
            inputField("Email", text: $email, isEmail: true)
            secureInput("Password", text: $password, placeholderRegister: "Password (12+ chars, mixed case, number, symbol)")
            if mode == .register {
                secureInput("Confirm password", text: $confirmPassword, placeholderRegister: "Confirm password")
            }
            if mode == .login {
                HStack {
                    Spacer()
                    Button("Forgot password?") {}
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            if let err = session.authErrorMessage, err.isEmpty == false {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            }

            Button(primaryButtonTitle) {
                submitEmail()
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(.black.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color.orange, Color(red: 1.0, green: 0.55, blue: 0.1)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .disabled(isEmailSubmitDisabled)
            .opacity(isEmailSubmitDisabled ? 0.5 : 1)
        }
    }

    private var socialDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)
            Text("or")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var googleButton: some View {
        Button {
            startGoogleSignIn()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Text("G")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black.opacity(0.75))
                    )
                if isGoogleSigningIn {
                    ProgressView()
                        .tint(.white.opacity(0.9))
                }
                Text("Continue with Google")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.2))
                    )
            )
        }
        .disabled(isGoogleSigningIn)
        .opacity(isGoogleSigningIn ? 0.7 : 1)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            Text(mode == .login ? "Don't have an account?" : "Already have an account?")
                .foregroundStyle(.secondary)
            Button(mode == .login ? "Sign up" : "Sign in") {
                mode = (mode == .login) ? .register : .login
                session.authErrorMessage = nil
            }
            .fontWeight(.semibold)
            .foregroundStyle(.orange)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }

    private func inputField(_ placeholder: String, text: Binding<String>, isEmail: Bool = false) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(isEmail ? .never : .words)
            .keyboardType(isEmail ? .emailAddress : .default)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12))
            )
            .foregroundStyle(.white)
    }

    private func secureInput(_ placeholder: String, text: Binding<String>, placeholderRegister: String? = nil) -> some View {
        SecureField(mode == .register ? (placeholderRegister ?? placeholder) : placeholder, text: text)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12))
            )
            .foregroundStyle(.white)
    }
}
