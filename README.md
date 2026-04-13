# Innsy 
Innsy is an iOS application that allows users to describe their ideal hotel experience or upload an image of
a desired view, and the app returns personalized hotel recommendations. The system shifts hotel search
from traditional filter‐based selection to intent‐driven discovery. I used the Gemma‐3‐12B‐it multimodal
model to interpret user intent and extract preferences from text and images, and integrated the Hotelbeds
API to retrieve and match real‐time hotel data based on those preferences.

[▶️ Watch Demo](https://drive.google.com/file/d/1u5Ga8AT7HkFWR-4Sl9adZup2LWlbrX6E/view)

---

## Requirements

- **macOS** with **Xcode** (project targets **iOS 18.2+** and **Swift 5**).
- Active accounts and credentials for the services below (see [APIs and services](#apis-and-services)).

---

## Swift packages 

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

### 3. Configure Hugging Face (Gemma)

1. Create a **Hugging Face** account and an access **token** with rights to invoke your endpoint.
2. Create or use an **Inference Endpoint** (or compatible server) running a **Gemma** model.
3. Edit **`Innsy/Secrets.swift`**:
   - `huggingFaceGemmaEndpoint` — base URL of the endpoint (no trailing path required; the app tries several API shapes).
   - `huggingFaceAccessToken` — `hf_…` token, **or** leave placeholder and paste the token in-app if your build stores it in UserDefaults (`UserOverrideKeys`).
   - `huggingFaceChatModelId` — if empty, the app tries several defaults; for **vLLM**-style endpoints, set this to the **exact** served model id.

### 4. Add `GoogleService-Info.plist` 

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

## Repository layout

| Path | Contents |
|------|-----------|
| `Innsy/` | SwiftUI app sources, `Secrets.swift`, assets. 
| `AppInfo.plist` | URL schemes and usage descriptions merged into the app. |

---

