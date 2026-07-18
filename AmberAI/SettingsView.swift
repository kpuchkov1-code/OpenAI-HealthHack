//
//  SettingsView.swift
//  AmberAI
//
//  The settings a shipping app carries: the signed-in account, the eMed membership,
//  the health profile, notifications, the load-bearing consent toggles, data
//  controls, support and about. Developer-only levers (inference keys, demo reset)
//  are tucked into an Advanced section so they never front the member's experience.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var wearables: WearableStore

    @State private var showProfileEditor = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var confirmReset = false

    // Advanced / developer.
    @State private var apiKey = RunwareConfig.apiKey
    @State private var openAIKey = OpenAIConfig.apiKey
    @State private var showAdvanced = false

    // Wearable credentials (entered in Advanced, stored like the inference keys).
    @State private var ouraToken = OuraConfig.personalToken
    @State private var ouraClientId = OuraConfig.clientId
    @State private var ouraClientSecret = OuraConfig.clientSecret
    @State private var whoopClientId = WhoopConfig.clientId
    @State private var whoopClientSecret = WhoopConfig.clientSecret

    private var profile: UserProfile { account.profile }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                membershipSection
                healthSection
                wearablesSection
                notificationsSection
                consentSection
                dataSection
                supportSection
                accountActionsSection
                aboutSection
                advancedSection
                demoTimeSection
            }
            .navigationTitle("Settings")
            .task {
                await wearables.refreshAll(connectedWearables)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditView(profile: account.profile) { updated in
                    account.save(updated)
                }
            }
            .alert("Sign out?", isPresented: $confirmSignOut) {
                Button("Sign out", role: .destructive) { account.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll return to the sign-in screen. Your data stays on this device.")
            }
            .alert("Delete account?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    account.deleteAccount()
                    app.reset()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes your profile and Amber's memory from this device. It cannot be undone.")
            }
            .alert("Reset the demo?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { app.reset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Restores the seeded memory and clears anything added this session. Your account is untouched.")
            }
            .alert("Couldn't connect", isPresented: Binding(
                get: { wearables.lastError != nil },
                set: { if !$0 { wearables.lastError = nil } })) {
                Button("OK", role: .cancel) { wearables.lastError = nil }
            } message: {
                Text(wearables.lastError ?? "")
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            Button {
                showProfileEditor = true
            } label: {
                HStack(spacing: 14) {
                    Circle()
                        .fill(Theme.amber.opacity(0.18))
                        .frame(width: 52, height: 52)
                        .overlay(Text(profile.initials)
                            .font(.headline).foregroundStyle(Theme.amber))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.fullName.isEmpty ? "Your name" : profile.fullName)
                            .font(.headline).foregroundStyle(Theme.ink)
                        Text(profile.email.isEmpty ? "Add your details" : profile.email)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .tint(Theme.ink)
        }
    }

    // MARK: - Membership

    private var membershipSection: some View {
        Section {
            LabeledContent("Programme", value: profile.plan.rawValue)
            if !profile.memberId.isEmpty {
                LabeledContent("Member ID", value: profile.memberId)
            }
            HStack {
                Label("At-home blood test", systemImage: "testtube.2")
                Spacer()
                Text(profile.homeTestOptIn ? "Enrolled" : "Off")
                    .foregroundStyle(profile.homeTestOptIn ? Theme.steady : .secondary)
            }
            Link(destination: URL(string: "https://www.emed.com")!) {
                Label("Manage membership", systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("eMed membership")
        } footer: {
            Text("Your at-home kit reads your metabolic markers at onboarding, 6 and 12 months, each reviewed by a clinician.")
        }
    }

    // MARK: - Health profile

    private var healthSection: some View {
        Section("Health profile") {
            LabeledContent("Approach", value: profile.management.display)
            if let start = profile.startWeightKg {
                LabeledContent("Starting weight", value: "\(foodNum(start)) kg")
            }
            if let goal = profile.goalWeightKg {
                LabeledContent("Goal weight", value: "\(foodNum(goal)) kg")
            }
            if !profile.medication.isEmpty {
                LabeledContent("Medication", value: profile.medication)
            }
            if let day = profile.injectionDay {
                LabeledContent("Injection day", value: day.weekdayName)
            }
            if !profile.prescriber.isEmpty {
                LabeledContent("Prescriber", value: profile.prescriber)
            }
            Button("Edit health details") { showProfileEditor = true }
                .tint(Theme.amber)
        }
    }

    // MARK: - Wearables

    private var connectedWearables: Set<Wearable> { profile.connectedWearables ?? [] }

    private var wearablesSection: some View {
        Section {
            wearableRow(.appleWatch)
            wearableRow(.oura)
            wearableRow(.whoop)
            comingSoonRow(.garmin)
        } header: {
            Text("Wearables")
        } footer: {
            Text("Connect a device so Amber sees your activity, sleep and recovery alongside your weight, and factors it into how it talks to you. Amber only reads — it never writes back. Apple Watch reads from Apple Health; Oura and WHOOP sign in to your account. Set up Oura/WHOOP credentials under Advanced. Garmin needs Garmin partner access, so it's not available yet.")
        }
    }

    /// One live wearable row. Apple Watch links to HealthKit; Oura and WHOOP sign in to
    /// their clouds. All three normalise into the same snapshot, so the row is generic.
    private func wearableRow(_ wearable: Wearable) -> some View {
        let isConnected = connectedWearables.contains(wearable)
        let canConnect = wearables.canConnect(wearable)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: wearable.icon)
                    .font(.title3)
                    .foregroundStyle(isConnected ? Theme.amber : .secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(wearable.rawValue).font(.subheadline.weight(.medium))
                    Text(wearable.detail)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if wearables.isWorking(wearable) {
                    ProgressView()
                } else {
                    Button(isConnected ? "Connected" : "Connect") {
                        Task { await toggleWearable(wearable, isConnected: isConnected) }
                    }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.borderless)
                    .tint(isConnected ? Theme.steady : Theme.amber)
                    .disabled(!isConnected && !canConnect)
                }
            }
            if isConnected {
                if let line = wearables.summaries[wearable]?.shortLine {
                    Text(line)
                        .font(.caption).foregroundStyle(Theme.steady)
                } else {
                    Text("Connected — waiting for data.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if !canConnect {
                Text(wearable == .appleWatch
                     ? "Health data isn't available on this device."
                     : "Add your \(wearable.rawValue) credentials under Advanced first.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Garmin: shown and described, but honestly not linkable — its Health API is gated
    /// behind Garmin partner approval, which this build can't complete.
    private func comingSoonRow(_ wearable: Wearable) -> some View {
        HStack(spacing: 14) {
            Image(systemName: wearable.icon)
                .font(.title3)
                .foregroundStyle(.tertiary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(wearable.rawValue).font(.subheadline.weight(.medium))
                Text(wearable.detail)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Coming soon")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Connect runs the real auth (HealthKit sheet or OAuth sign-in) and only sets the
    /// connected flag once it succeeds. Disconnect stops Amber reading the device.
    private func toggleWearable(_ wearable: Wearable, isConnected: Bool) async {
        if isConnected {
            wearables.disconnect(wearable)
            account.setWearable(wearable, connected: false)
            app.wearableSummaries = wearables.allSummaries
        } else {
            let ok = await wearables.connect(wearable)
            if ok {
                account.setWearable(wearable, connected: true)
                app.wearableSummaries = wearables.allSummaries
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { account.profile.checkInReminders },
                set: { var p = account.profile; p.checkInReminders = $0; account.save(p) })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Check-in reminders").font(.subheadline.weight(.medium))
                    Text("A gentle nudge if a few days go quiet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Theme.amber)
        } header: {
            Text("Notifications")
        }
    }

    // MARK: - Consent (load-bearing)

    private var consentSection: some View {
        Section {
            consentRow(
                title: "Remember my life outside my weight loss",
                subtitle: "Off: personal facts never reach the model. Amber stops knowing about Biscuit, Lisbon, the wedding.",
                isOn: Binding(get: { app.state.consent.rememberPersonal },
                              set: { app.setRememberPersonal($0) }))
            consentRow(
                title: "Let Amber reach out first",
                subtitle: "Off: no unprompted opener, however long the silence.",
                isOn: Binding(get: { app.state.consent.proactiveOutreach },
                              set: { app.setProactiveOutreach($0) }))
            consentRow(
                title: "Share support signals with my care team",
                subtitle: "Off: the eMed screen shows nothing at all. Core service unaffected.",
                isOn: Binding(get: { app.state.consent.shareWithClinician },
                              set: { app.setShareWithClinician($0) }))
        } header: {
            Text("Privacy & consent")
        } footer: {
            if app.consentCost > 0 {
                Text("Right now \(app.consentCost) fact\(app.consentCost == 1 ? "" : "s") \(app.consentCost == 1 ? "is" : "are") withheld from the model by these choices, at week \(app.week).")
                    .foregroundStyle(Theme.support)
            } else {
                Text("A consent you cannot refuse without losing what you paid for is not freely given. Refusing any of these costs you nothing else.")
            }
        }
    }

    // MARK: - Data & privacy

    private var dataSection: some View {
        Section("Data & privacy") {
            ShareLink(item: exportText,
                      preview: SharePreview("Amber data export")) {
                Label("Export my data", systemImage: "square.and.arrow.up")
            }
            .tint(Theme.amber)
            Link(destination: URL(string: "https://amber-ai-kpuchkov1-3058s-projects.vercel.app/privacy")!) {
                Label("Privacy policy", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "https://amber-ai-kpuchkov1-3058s-projects.vercel.app/terms")!) {
                Label("Terms of use", systemImage: "doc.text")
            }
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        Section("Support") {
            Link(destination: URL(string: "https://www.emed.com/contact")!) {
                Label("Help centre", systemImage: "questionmark.circle")
            }
            Link(destination: URL(string: "mailto:support@emed.com")!) {
                Label("Contact support", systemImage: "envelope")
            }
        }
    }

    // MARK: - Account actions

    private var accountActionsSection: some View {
        Section {
            Button { confirmSignOut = true } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .tint(Theme.ink)
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete account", systemImage: "trash")
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
        } footer: {
            Text("Amber for eMed · a companion for people on a weight-loss programme.")
        }
    }

    // MARK: - Advanced (developer)

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                SecureField("Runware API key", text: $apiKey)
                    .onSubmit { RunwareConfig.apiKey = apiKey }
                Button("Save Runware key") { RunwareConfig.apiKey = apiKey }
                    .disabled(apiKey == RunwareConfig.apiKey)
                    .tint(Theme.amber)

                SecureField("OpenAI Realtime key", text: $openAIKey)
                    .onSubmit { OpenAIConfig.apiKey = openAIKey }
                Button("Save OpenAI key") { OpenAIConfig.apiKey = openAIKey }
                    .disabled(openAIKey == OpenAIConfig.apiKey)
                    .tint(Theme.amber)

                wearableCredentials

                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Reset the demo", systemImage: "arrow.counterclockwise")
                }
            }
        } footer: {
            Text("Runware powers Amber's brain and voice; OpenAI powers real-time Talk. Speech-to-text runs on-device. Oura/WHOOP need an app you register with each service (redirect amberai://oura and amberai://whoop). These controls are for the demo build only.")
        }
    }

    /// Credentials for the cloud wearables. Oura takes a legacy Personal Access Token or an
    /// OAuth client id/secret; WHOOP is OAuth only. Stored like the inference keys above.
    @ViewBuilder private var wearableCredentials: some View {
        SecureField("Oura personal token (legacy)", text: $ouraToken)
            .onSubmit { OuraConfig.personalToken = ouraToken }
        SecureField("Oura OAuth client ID", text: $ouraClientId)
        SecureField("Oura OAuth client secret", text: $ouraClientSecret)
        Button("Save Oura credentials") {
            OuraConfig.personalToken = ouraToken
            OuraConfig.clientId = ouraClientId
            OuraConfig.clientSecret = ouraClientSecret
        }
        .disabled(ouraToken == OuraConfig.personalToken
                  && ouraClientId == OuraConfig.clientId
                  && ouraClientSecret == OuraConfig.clientSecret)
        .tint(Theme.amber)

        SecureField("WHOOP OAuth client ID", text: $whoopClientId)
        SecureField("WHOOP OAuth client secret", text: $whoopClientSecret)
        Button("Save WHOOP credentials") {
            WhoopConfig.clientId = whoopClientId
            WhoopConfig.clientSecret = whoopClientSecret
        }
        .disabled(whoopClientId == WhoopConfig.clientId
                  && whoopClientSecret == WhoopConfig.clientSecret)
        .tint(Theme.amber)
    }

    // MARK: - Demo: time travel

    /// The programme-week scrubber, relocated here from Memory. Load-bearing for the
    /// demo — landing on an earlier week makes Amber genuinely forget anything learned
    /// after it, because memory is filtered by time everywhere, not reworded.
    private var demoTimeSection: some View {
        Section {
            WeekScrubber()
                .listRowBackground(Color.clear)
        } header: {
            Text("Demo · time travel")
        } footer: {
            Text("Scrub the programme week. Amber forgets anything learned after the week you land on — every screen reads the same clock.")
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// A neatly formatted, progress-first export of the member's programme. Leads with the
    /// numbers she actually tracks — weight, habits, meals — and closes with a short summary
    /// of what Amber remembers, rather than dumping every stored fact.
    private var exportText: String {
        var out: [String] = []

        func rule() { out.append(String(repeating: "─", count: 34)) }
        func heading(_ t: String) { out.append(""); out.append(t.uppercased()); rule() }

        // Header
        out.append("AMBER — MY PROGRESS EXPORT")
        rule()
        out.append("Generated \(Date().formatted(date: .abbreviated, time: .omitted))")
        out.append("Programme \(profile.plan.rawValue) · \(app.weekLabel)")

        // Member
        heading("Member")
        if !profile.fullName.isEmpty { out.append("Name          \(profile.fullName)") }
        if !profile.email.isEmpty { out.append("Email         \(profile.email)") }
        if !profile.memberId.isEmpty { out.append("Member ID     \(profile.memberId)") }
        out.append("Approach      \(profile.management.display)")
        if !profile.medication.isEmpty { out.append("Medication    \(profile.medication)") }
        if let day = profile.injectionDay { out.append("Injection day \(day.weekdayName)") }
        if !profile.prescriber.isEmpty { out.append("Prescriber    \(profile.prescriber)") }

        // Weight progress
        heading("Weight progress")
        let start = profile.startWeightKg ?? firstWeight(app.state.weightEntries, app.week)?.kg
        let latest = app.currentWeight
        if let start { out.append("Starting weight  \(foodNum(start)) kg") }
        if let latest { out.append("Latest weigh-in  \(foodNum(latest.kg)) kg (week \(latest.week))") }
        if let start, let latest {
            let delta = latest.kg - start
            let dir = delta < 0 ? "down" : (delta > 0 ? "up" : "level")
            out.append("Change so far    \(dir == "level" ? "" : (delta < 0 ? "−" : "+"))\(foodNum(abs(delta))) kg (\(dir))")
        }
        if let goal = profile.goalWeightKg {
            out.append("Goal weight      \(foodNum(goal)) kg")
            if let start, let latest, start - goal > 0 {
                let pct = Int((max(0, min(1, (start - latest.kg) / (start - goal))) * 100).rounded())
                out.append("Toward goal      \(pct)%")
            }
        }
        let series = weightSeries(app.state.weightEntries, app.week)
        if series.count > 1 {
            out.append("")
            out.append("Recent weigh-ins")
            for e in series.suffix(6) {
                out.append("  Week \(e.week), \(e.day.weekdayName): \(foodNum(e.kg)) kg")
            }
        } else if latest == nil {
            out.append("No weigh-ins logged yet.")
        }

        // Habits this week
        heading("Habits · this week")
        let habits = activeHabits(app.state.habits, app.week)
        if habits.isEmpty {
            out.append("No habits set yet.")
        } else {
            let weeks = habits.map { habitWeek($0, app.state.checkIns, app.week, app.state.foodEntries) }
            out.append("On track: \(weeks.filter { $0.met }.count) of \(habits.count)")
            out.append("")
            for hw in weeks {
                let mark = hw.met ? "✓" : "•"
                let aim = hw.habit.direction == .atMost ? "≤\(hw.habit.target)/wk" : "\(hw.habit.target)/wk"
                out.append("  \(mark) \(hw.habit.label) — \(hw.count) of \(hw.habit.target) (\(aim))")
            }
        }

        // Food logging
        heading("Food logging")
        let allMeals = app.state.foodEntries.filter { $0.week <= app.week }
        let thisWeekMeals = allMeals.filter { $0.week == app.week }
        out.append("Meals logged this week   \(thisWeekMeals.count)")
        out.append("Meals logged in total    \(allMeals.count)")

        // What Amber remembers (summary only)
        heading("What Amber remembers")
        out.append("Amber holds \(app.knownCount) fact\(app.knownCount == 1 ? "" : "s") about you at \(app.weekLabel).")
        let live = app.displayedFacts.filter { $0.forgotten != true }
        let byType = FactType.allCases
            .map { t in (t, live.filter { $0.type == t }.count) }
            .filter { $0.1 > 0 }
        for (type, count) in byType {
            out.append("  \(type.display): \(count)")
        }
        if app.consentCost > 0 {
            out.append("")
            out.append("\(app.consentCost) fact\(app.consentCost == 1 ? " is" : "s are") withheld from the model by your consent choices.")
        }

        out.append("")
        rule()
        out.append("Your data stays on your device. Export made from Settings → Export my data.")
        return out.joined(separator: "\n")
    }

    private func consentRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(Theme.amber)
    }
}

// MARK: - Profile editor

/// Edits the member's account and health details on a working copy, committing only
/// when they tap Save. Mirrors the fields onboarding captured.
struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: UserProfile
    let onSave: (UserProfile) -> Void

    /// Bridges a kilograms Double? to a text field.
    private func kgBinding(_ source: Binding<Double?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue.map { foodNum($0) } ?? "" },
            set: { source.wrappedValue = Double($0.replacingOccurrences(of: ",", with: ".")) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("First name", text: $profile.firstName)
                        .textContentType(.givenName)
                    TextField("Last name", text: $profile.lastName)
                        .textContentType(.familyName)
                    TextField("Email", text: $profile.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }

                Section("Weight & approach") {
                    Picker("Approach", selection: $profile.management) {
                        ForEach(ManagementApproach.allCases) { Text($0.display).tag($0) }
                    }
                    HStack {
                        Text("Starting weight")
                        Spacer()
                        TextField("kg", text: kgBinding($profile.startWeightKg))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Goal weight")
                        Spacer()
                        TextField("kg", text: kgBinding($profile.goalWeightKg))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg").foregroundStyle(.secondary)
                    }
                }

                Section("Medication") {
                    TextField("Medication", text: $profile.medication)
                    Picker("Injection day", selection: Binding(
                        get: { profile.injectionDay ?? -1 },
                        set: { profile.injectionDay = $0 == -1 ? nil : $0 })) {
                        Text("Not applicable").tag(-1)
                        ForEach(0..<7, id: \.self) { Text($0.weekdayName).tag($0) }
                    }
                }

                Section("eMed membership") {
                    Picker("Programme", selection: $profile.plan) {
                        ForEach(MembershipPlan.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Member ID", text: $profile.memberId)
                        .textInputAutocapitalization(.never)
                    TextField("Prescriber", text: $profile.prescriber)
                    Toggle("At-home blood test kit", isOn: $profile.homeTestOptIn)
                        .tint(Theme.amber)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(profile); dismiss() }
                        .tint(Theme.amber)
                }
            }
        }
    }
}
