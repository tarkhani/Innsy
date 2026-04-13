import Foundation

enum UserOverrideKeys {
    static let huggingFaceAccessToken = "Innsy.huggingFaceAccessToken"
}

enum ResolvedLLMKeys {
    static var huggingFaceAccessToken: String {
        let fromApp = UserDefaults.standard.string(forKey: UserOverrideKeys.huggingFaceAccessToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if fromApp.isEmpty == false { return fromApp }
        let s = Secrets.huggingFaceAccessToken
        if s.starts(with: "YOUR_") || s.isEmpty { return "" }
        return s
    }
}
