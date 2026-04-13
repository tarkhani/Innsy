//
//  GoogleSignInManager.swift
//  Innsy
//

import Foundation
import GoogleSignIn
import UIKit

enum GoogleSignInManager {
    /// Same value as `kGIDSignInErrorDomain` in the SDK (`GIDSignInErrorDomain` is not always imported into Swift).
    private static let googleSignInErrorDomain = "com.google.GIDSignIn"

    /// `kGIDSignInErrorCodeCanceled` is `-5`.
    static func isUserCanceledSignIn(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == googleSignInErrorDomain && ns.code == -5
    }

    static func configureFromGoogleServicePlist() {
        guard
            let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let plist = NSDictionary(contentsOfFile: path),
            let clientID = plist["CLIENT_ID"] as? String
        else {
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    static func handle(url: URL) {
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? scene.windows.first?.rootViewController
        else {
            return nil
        }
        return findTop(from: root)
    }

    @MainActor
    static func signIn(presenting viewController: UIViewController) async throws -> (email: String, displayName: String?) {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let user = result?.user, let profile = user.profile else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "Innsy",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Google did not return profile data."]
                        )
                    )
                    return
                }
                let email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
                guard email.isEmpty == false else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "Innsy",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Google did not return an email address."]
                        )
                    )
                    return
                }
                let nameTrimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName: String? = nameTrimmed.isEmpty ? nil : nameTrimmed
                continuation.resume(returning: (email, displayName))
            }
        }
    }

    @MainActor
    private static func findTop(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return findTop(from: presented)
        }
        if let nav = controller as? UINavigationController, let visible = nav.visibleViewController {
            return findTop(from: visible)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return findTop(from: selected)
        }
        return controller
    }
}
