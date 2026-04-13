//
//  InnsyApp.swift
//  Innsy
//
//  Created by Ahmadreza Tarkhani on 09/04/2026.
//

import SwiftUI

@main
struct InnsyApp: App {
    @StateObject private var session = UserSessionViewModel()

    init() {
        GoogleSignInManager.configureFromGoogleServicePlist()
    }
    private var startupPipeline: HotelbedsHotelPipeline {
        let env = HotelbedsEnvironment(useTestHosts: Secrets.hotelbedsUseTestEnvironment)
        let client = HotelbedsAPIClient(
            environment: env,
            apiKey: Secrets.hotelbedsAPIKey,
            secret: Secrets.hotelbedsSecret
        )
        return HotelbedsHotelPipeline(client: client)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onOpenURL { url in
                    GoogleSignInManager.handle(url: url)
                }
                .task {
                    await FacilityCodebookStore.shared.preloadIfNeeded(using: startupPipeline)
                }
        }
    }
}
