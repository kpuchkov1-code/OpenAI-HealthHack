//
//  AmberAIApp.swift
//  AmberAI
//
//  Amber — the companion that remembers. A voice companion for people on a long
//  eMed weight-loss programme, ported to iOS from the Ember web app.
//

import SwiftUI

@main
struct AmberAIApp: App {
    @StateObject private var app = AppState()
    @StateObject private var account = AccountStore()
    @StateObject private var wearables = WearableStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(account)
                .environmentObject(wearables)
                // Read every connected wearable once on launch, then keep AppState's copies
                // in step so both the text and voice prompts see them.
                .task {
                    await wearables.refreshAll(account.profile.connectedWearables ?? [])
                }
                .onChange(of: wearables.summaries) { _, _ in
                    app.wearableSummaries = wearables.allSummaries
                }
        }
    }
}

/// Decides between first-run onboarding and the app itself. Gating on the account's
/// persisted flag means sign-out and delete-account both land back here cleanly.
struct RootView: View {
    @EnvironmentObject var account: AccountStore

    var body: some View {
        if account.onboardingComplete {
            ContentView()
        } else {
            OnboardingView()
        }
    }
}
