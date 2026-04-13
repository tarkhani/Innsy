# Innsy (HotelLLm)

SwiftUI iOS app for describing a stay in natural language, extracting structured booking intent with a Gemma model on **Hugging Face Inference Endpoints**, and searching or booking via the **Hotelbeds (HBX)** APIs. **Google Sign-In** is optional for account sign-in.

---

## Requirements

- **macOS** with **Xcode** (project targets **iOS 18.2+** and **Swift 5**).
- Active accounts and credentials for the services below (see [APIs and services](#apis-and-services)).

---

## Swift packages (libraries)

Dependencies are managed with **Swift Package Manager** inside Xcode. The app target links **GoogleSignIn** from [GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS) (resolved version in `Innsy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`).

Transitive packages pulled in by that graph typically include:

| Package | Purpose |
|--------|---------|
| **GoogleSignIn** | Google OAuth on iOS. |
| **AppAuth** | OAuth 2.0 / OpenID client. |
| **GTMAppAuth** | Google utilities on top of AppAuth. |
| **GTMSessionFetcher** | HTTP session helpers used by Google libraries. |
| **GoogleUtilities** | Shared Google iOS utilities. |
| **Promises** | Async promise/future helpers used by Google libraries. |
| **AppCheck** | App attestation (dependency of the Google stack). |

After cloning, open the project and let Xcode resolve packages: **File → Packages → Resolve Package Versions** (or build once).

---

## APIs and services

| API / service | What the app uses it for |
|----------------|---------------------------|
| **Hotelbeds (HBX)** | Hotel **content**, **availability**, and **booking** HTTP APIs. You need an API key and secret from the [Hotelbeds developer dashboard](https://developer.hotelbeds.com/) (Hotel API / HBX, not unrelated products). |
| **Hugging Face** | **Inference Endpoint** hosting **Gemma** (multimodal-capable) for JSON-style **booking intent** extraction. You need the endpoint **base URL** and an access **token** with permission to call it. Optional: set `huggingFaceChatModelId` in `Secrets.swift` if your server expects a specific OpenAI-style `model` name (e.g. vLLM). |
| **Google Sign-In + Firebase** | **Google Sign-In** reads **`CLIENT_ID`** from **`GoogleService-Info.plist`**. That file is produced when you register an iOS app in **[Firebase Console](https://console.firebase.google.com/)** (or the linked Google Cloud OAuth client). Firebase itself is not required for every feature, but downloading the plist from Firebase is the usual way to get a valid iOS OAuth client configuration. |

The repository includes an example handler for a custom endpoint: `HotelLLm/inference-endpoint/gemma3_multimodal_handler.example.py` (deploy and point your HF endpoint at it per Hugging Face docs).

---

## Step-by-step: make the app run

### 1. Open the project

1. Clone this repository.
2. Open **`HotelLLm/Innsy.xcodeproj`** in Xcode.
3. Wait for Swift packages to resolve; fix any “package resolution” prompts if Xcode asks.

### 2. Configure Hotelbeds

1. Sign up at [developer.hotelbeds.com](https://developer.hotelbeds.com/) and create **Hotel / HBX** API credentials (key + secret).
2. Edit **`Innsy/Secrets.swift`**:
   - Set `hotelbedsAPIKey` and `hotelbedsSecret`.
   - Set `hotelbedsUseTestEnvironment` to `true` for sandbox hosts, or `false` for production (see Hotelbeds documentation).

Without valid keys, hotel search and booking flows that call Hotelbeds will fail at runtime.

### 3. Configure Hugging Face (Gemma / intent parsing)

1. Create a **Hugging Face** account and an access **token** with rights to invoke your endpoint.
2. Create or use an **Inference Endpoint** (or compatible server) running a **Gemma** model suited to your handler (see `inference-endpoint/gemma3_multimodal_handler.example.py` and comments in `HuggingFaceGemmaIntentService.swift`).
3. Edit **`Innsy/Secrets.swift`**:
   - `huggingFaceGemmaEndpoint` — base URL of the endpoint (no trailing path required; the app tries several API shapes).
   - `huggingFaceAccessToken` — `hf_…` token, **or** leave placeholder and paste the token in-app if your build stores it in UserDefaults (`UserOverrideKeys`).
   - `huggingFaceChatModelId` — if empty, the app tries several defaults; for **vLLM**-style endpoints, set this to the **exact** served model id.

### 4. Add `GoogleService-Info.plist` (not in git)

This file is **not** committed. You must add it locally:

1. In [Firebase Console](https://console.firebase.google.com/), create a project (or use an existing one).
2. Add an **iOS app** whose **bundle ID** matches Xcode (**`tarkhani.Innsy`** unless you change `PRODUCT_BUNDLE_IDENTIFIER` in the project).
3. Download **`GoogleService-Info.plist`**.
4. Drag it into the Xcode group **`Innsy`** (same folder as `Secrets.swift`), ensure **“Copy items if needed”** is checked and the **Innsy** app target is ticked.

`GoogleSignInManager` loads it at launch; if the file is missing, **Google Sign-In** will not be configured (email/password auth can still be used if implemented in-app).

### 5. URL scheme for Google Sign-In

Google Sign-In needs a **URL type** matching **`REVERSED_CLIENT_ID`** from `GoogleService-Info.plist`.

1. Open **`AppInfo.plist`** (in the `HotelLLm` folder next to the `.xcodeproj`).
2. Under **URL types** → **URL Schemes**, set the scheme to the **exact** `REVERSED_CLIENT_ID` string from your plist (format `com.googleusercontent.apps.<numbers>-<suffix>`).

If this does not match, the redirect after Google login will not return to the app.

### 6. Build and run

1. Select a simulator or device (iOS **18.2+**).
2. **Product → Run**.

Fix compile errors in `Secrets.swift` if placeholders are still present and you need a successful build for other work—replace every `YOUR_…` value with real credentials or temporarily use test values you control.

---

## Optional: Hugging Face token only in the app

Users can store a Hugging Face token at runtime instead of (or overriding) `Secrets.huggingFaceAccessToken`. See **`UserOverrideKeys`** / **`ResolvedLLMKeys`** in the source for how UserDefaults overrides the compile-time secret.

---

## Repository layout

| Path | Contents |
|------|-----------|
| `HotelLLm/Innsy/` | SwiftUI app sources, `Secrets.swift`, assets. |
| `HotelLLm/inference-endpoint/` | Example Python endpoint handler for Gemma 3 multimodal. |
| `HotelLLm/AppInfo.plist` | URL schemes and usage descriptions merged into the app. |

---

## Security notes

- Never commit real **`GoogleService-Info.plist`**, Hotelbeds secrets, or Hugging Face tokens.
- Restrict **Hotelbeds** keys and **Firebase** API keys in each vendor’s console (IP, bundle ID, etc.) per their documentation.
