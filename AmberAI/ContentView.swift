//
//  ContentView.swift
//  AmberAI
//
//  The patient-facing app: five tabs. The eMed clinician screen is deliberately not a
//  tab — it is a different product, reached from Settings.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HabitsView()
                .tabItem { Label("Habits", systemImage: "checklist") }
            MemoryView()
                .tabItem { Label("Memory", systemImage: "brain.head.profile") }
            TalkView()
                .tabItem { Label("Talk", systemImage: "waveform") }
            RecordsView()
                .tabItem { Label("Records", systemImage: "doc.text") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.amber)
        // Amber's patient app is a light-themed product. Pin the scheme so the
        // custom cream/white surfaces never get white system text painted on them,
        // and so Settings' Form doesn't render dark on a dark-mode device.
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(AccountStore())
}
