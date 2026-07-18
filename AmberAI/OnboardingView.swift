//
//  OnboardingView.swift
//  AmberAI
//
//  First run. A seven-step flow that stands up an account, captures the member's
//  weight-loss context, enrols them on their eMed programme, and takes the
//  three load-bearing consent decisions up front. Every answer is written to the
//  profile or to consent — nothing here is decoration.
//
//  Presentation: centred, unhurried, premium. Steps cross-fade and slide, the
//  chrome stays quiet, and the eye is always pulled to the middle of the screen.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var account: AccountStore

    /// A draft the whole flow edits, seeded from whatever is already on disk so a
    /// returning member (after sign-out) sees their details prefilled.
    @State private var draft: UserProfile
    @State private var password = ""
    @State private var step = 0
    /// Direction of the last navigation, so the transition slides the right way.
    @State private var forward = true

    // Consent decisions, defaulted to the app's current values.
    @State private var rememberPersonal: Bool
    @State private var proactiveOutreach: Bool
    @State private var shareWithClinician: Bool

    @FocusState private var focused: Bool

    private let lastStep = 6

    init() {
        _draft = State(initialValue: .demo)
        _rememberPersonal = State(initialValue: true)
        _proactiveOutreach = State(initialValue: true)
        _shareWithClinician = State(initialValue: true)
    }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    stepContent
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                        .padding(.horizontal, 28)
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity)
                }
                footer
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            draft = account.profile
            rememberPersonal = app.state.consent.rememberPersonal
            proactiveOutreach = app.state.consent.proactiveOutreach
            shareWithClinician = app.state.consent.shareWithClinician
        }
    }

    // MARK: - Chrome

    /// A soft cream field with a single warm glow behind the content — calm, premium.
    private var backdrop: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(
                colors: [Theme.amberSoft.opacity(0.35), .clear],
                center: .top, startRadius: 0, endRadius: 460)
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.7), in: Circle())
            }
            .opacity(step > 0 ? 1 : 0)
            .disabled(step == 0)

            Spacer(minLength: 12)

            // Segmented progress — quiet, evenly weighted, fills as you go.
            HStack(spacing: 5) {
                ForEach(0...lastStep, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Theme.amber : Theme.amber.opacity(0.18))
                        .frame(width: i == step ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
                }
            }

            Spacer(minLength: 12)

            // Balances the back button so the progress stays centred.
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Button {
                advance()
            } label: {
                Text(step == lastStep ? "Get started" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(canAdvance ? Theme.amber : Theme.amber.opacity(0.35)))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.amber.opacity(canAdvance ? 0.35 : 0),
                            radius: 14, y: 8)
            }
            .disabled(!canAdvance)
            .animation(.easeInOut(duration: 0.2), value: canAdvance)

            Button {
                advance()
            } label: {
                Text("Skip for now")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
            .opacity(skippable ? 1 : 0)
            .disabled(!skippable)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .padding(.top, 8)
    }

    // MARK: - Flow control

    private var canAdvance: Bool {
        switch step {
        case 1:
            return !draft.firstName.trimmingCharacters(in: .whitespaces).isEmpty
                && draft.email.contains("@") && draft.email.contains(".")
                && password.count >= 8
        default:
            return true
        }
    }

    /// Medical steps can be skipped; the account step cannot.
    private var skippable: Bool { step == 3 || step == 4 }

    private func advance() {
        focused = false
        if step == lastStep {
            finish()
        } else {
            forward = true
            withAnimation(.easeInOut(duration: 0.32)) { step += 1 }
        }
    }

    private func back() {
        focused = false
        forward = false
        withAnimation(.easeInOut(duration: 0.32)) { step = max(0, step - 1) }
    }

    private func finish() {
        draft.firstName = draft.firstName.trimmingCharacters(in: .whitespaces)
        draft.lastName = draft.lastName.trimmingCharacters(in: .whitespaces)
        draft.email = draft.email.trimmingCharacters(in: .whitespaces)
        app.setRememberPersonal(rememberPersonal)
        app.setProactiveOutreach(proactiveOutreach)
        app.setShareWithClinician(shareWithClinician)
        account.completeOnboarding(with: draft)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: accountStep
        case 2: weightStep
        case 3: medicationStep
        case 4: emedStep
        case 5: consentStep
        default: readyStep
        }
    }

    // 0 — Welcome
    private var welcomeStep: some View {
        VStack(spacing: 22) {
            heroIcon("waveform", tint: Theme.amber)
            title("Meet Amber")
            subtitle("The companion inside your eMed weight-loss programme. It remembers what you tell it — your medication, your hard days, the small wins — so you never explain yourself twice.")
            VStack(spacing: 12) {
                feature("waveform", "Talk or type, whenever it suits you")
                feature("brain.head.profile", "Remembers your context between chats")
                feature("cross.case", "Alongside your eMed care team, never instead of it")
            }
            .padding(.top, 4)
            footnote("Setup takes about two minutes.")
        }
    }

    // 1 — Account
    private var accountStep: some View {
        VStack(spacing: 20) {
            heroIcon("person.crop.circle", tint: Theme.amber)
            title("Create your account")
            subtitle("This is the account your eMed membership and your data belong to.")
            VStack(spacing: 12) {
                field("First name", text: $draft.firstName, content: .givenName)
                field("Last name", text: $draft.lastName, content: .familyName)
                field("Email", text: $draft.email, content: .emailAddress,
                      keyboard: .emailAddress, autocap: false)
                secureField("Password", text: $password)
            }
            footnote(password.isEmpty || password.count >= 8
                     ? "Use at least 8 characters."
                     : "A little longer — at least 8 characters.")
        }
    }

    // 2 — Weight
    private var weightStep: some View {
        VStack(spacing: 20) {
            heroIcon("figure.walk", tint: Theme.amber)
            title("Your weight")
            subtitle("A little context so Amber and your clinician start on the same page. Skip anything you'd rather not share.")

            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    label("Starting weight (kg)")
                    field("Starting weight", text: kgBinding($draft.startWeightKg),
                          content: .none, keyboard: .decimalPad, placeholder: "e.g. 95", autocap: false)
                }
                VStack(spacing: 8) {
                    label("Goal weight (kg), optional")
                    field("Goal weight", text: kgBinding($draft.goalWeightKg),
                          content: .none, keyboard: .decimalPad, placeholder: "e.g. 78", autocap: false)
                }
            }

            VStack(spacing: 10) {
                label("How are you approaching it?")
                ForEach(ManagementApproach.allCases) { option in
                    selectCard(
                        title: option.display,
                        subtitle: option.detail,
                        selected: draft.management == option) {
                            withAnimation(.easeInOut(duration: 0.15)) { draft.management = option }
                        }
                }
            }
            .padding(.top, 4)
        }
    }

    /// Bridges a kilograms Double? to the text `field` helper.
    private func kgBinding(_ source: Binding<Double?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue.map { foodNum($0) } ?? "" },
            set: { source.wrappedValue = Double($0.replacingOccurrences(of: ",", with: ".")) })
    }

    // 3 — Medication
    private var medicationStep: some View {
        VStack(spacing: 20) {
            heroIcon("pills", tint: Theme.amber)
            title("Your medication")
            subtitle("On a GLP-1 or another weight-loss medication? Tell Amber what and when. You can change this any time.")
            VStack(spacing: 12) {
                field("Medication", text: $draft.medication, content: .none,
                      placeholder: "e.g. Mounjaro (tirzepatide)")
                VStack(spacing: 8) {
                    label("Weekly injection day")
                    menuField {
                        Picker("Injection day", selection: Binding(
                            get: { draft.injectionDay ?? -1 },
                            set: { draft.injectionDay = $0 == -1 ? nil : $0 })) {
                            Text("Not applicable").tag(-1)
                            ForEach(0..<7, id: \.self) { Text($0.weekdayName).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
    }

    // 4 — eMed programme + at-home test
    private var emedStep: some View {
        VStack(spacing: 20) {
            heroIcon("cross.case", tint: Theme.amber)
            title("Your eMed programme")
            subtitle("Connect this app to your eMed membership. Your care team sees only what you allow — you set that next.")

            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    label("Programme")
                    menuField {
                        Picker("Programme", selection: $draft.plan) {
                            ForEach(MembershipPlan.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                    }
                    Text(draft.plan.blurb)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                field("Member ID", text: $draft.memberId, content: .none,
                      placeholder: "e.g. EM-4021-7788", autocap: false)
                field("Prescribing clinician", text: $draft.prescriber, content: .none,
                      placeholder: "e.g. Dr Patel")

                testKitCard
            }
        }
    }

    private var testKitCard: some View {
        VStack(spacing: 10) {
            Toggle(isOn: $draft.homeTestOptIn) {
                HStack(spacing: 10) {
                    Image(systemName: "testtube.2").foregroundStyle(Theme.amber)
                    Text("Send my at-home blood test kit")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                }
            }
            .tint(Theme.amber)
            Text("eMed ships a finger-prick kit at onboarding, 6 and 12 months. It reads your metabolic markers, reviewed by a clinician.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(card)
    }

    // 5 — Consent
    private var consentStep: some View {
        VStack(spacing: 20) {
            heroIcon("hand.raised", tint: Theme.amber)
            title("Your privacy")
            subtitle("Three real choices. Each one genuinely changes what Amber can do — and you can change any of them later in Settings.")
            VStack(spacing: 12) {
                consentToggle(
                    title: "Remember my life outside my weight loss",
                    subtitle: "Personal context — your dog, your holiday, a wedding. Off: only clinical facts are kept.",
                    isOn: $rememberPersonal)
                consentToggle(
                    title: "Let Amber reach out first",
                    subtitle: "It can open a conversation after a quiet stretch. Off: it only ever replies.",
                    isOn: $proactiveOutreach)
                consentToggle(
                    title: "Share support signals with my care team",
                    subtitle: "Your clinician sees plain-language signals from what you've said. Off: the care team screen shows nothing. Your care is unchanged either way.",
                    isOn: $shareWithClinician)
            }
        }
    }

    // 6 — Ready
    private var readyStep: some View {
        VStack(spacing: 20) {
            heroIcon("checkmark", tint: Theme.steady)
            title(draft.firstName.isEmpty ? "You're all set" : "You're all set, \(draft.firstName)")
            subtitle("Amber is ready. Here's what it'll start with:")
            VStack(spacing: 12) {
                summaryRow("person.text.rectangle", draft.fullName.isEmpty ? "Account created" : draft.fullName)
                summaryRow("cross.case", "\(draft.plan.rawValue) with eMed")
                if !draft.medication.isEmpty {
                    summaryRow("pills", draft.medication)
                }
                summaryRow("hand.raised", "\(activeConsents) of 3 sharing options on")
                if draft.homeTestOptIn {
                    summaryRow("testtube.2", "At-home blood test kit on its way")
                }
            }
            footnote("You can change any of this in Settings whenever you like.")
        }
    }

    // MARK: - Building blocks

    private var activeConsents: Int {
        [rememberPersonal, proactiveOutreach, shareWithClinician].filter { $0 }.count
    }

    /// Shared card surface — soft white, faint warm border, gentle lift.
    private var card: some ShapeStyle { .white }

    private func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.white)
            .shadow(color: Theme.ink.opacity(0.05), radius: 10, y: 4)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.amberSoft.opacity(0.45)))
    }

    private func heroIcon(_ icon: String, tint: Color) -> some View {
        Circle()
            .fill(tint.opacity(0.14))
            .frame(width: 88, height: 88)
            .overlay(Image(systemName: icon)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(tint))
            .shadow(color: tint.opacity(0.18), radius: 16, y: 8)
            .padding(.bottom, 2)
    }

    private func title(_ t: String) -> some View {
        Text(t)
            .font(.system(.largeTitle, design: .rounded).weight(.bold))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func subtitle(_ t: String) -> some View {
        Text(t)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .frame(maxWidth: 340)
    }

    private func footnote(_ t: String) -> some View {
        Text(t)
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    private func label(_ t: String) -> some View {
        Text(t)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private func feature(_ icon: String, _ t: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 34, height: 34)
                .background(Theme.amber.opacity(0.12), in: Circle())
            Text(t)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(cardBackground())
    }

    private func summaryRow(_ icon: String, _ t: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 30)
            Text(t)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(cardBackground())
    }

    private func field(_ label: String, text: Binding<String>,
                       content: UITextContentType?, keyboard: UIKeyboardType = .default,
                       placeholder: String = "", autocap: Bool = true) -> some View {
        TextField(placeholder.isEmpty ? label : placeholder, text: text)
            .focused($focused)
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocap ? .sentences : .never)
            .autocorrectionDisabled(!autocap)
            .multilineTextAlignment(.center)
            .font(.system(.body, design: .rounded))
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .background(cardBackground())
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        SecureField(label, text: text)
            .focused($focused)
            .textContentType(.newPassword)
            .multilineTextAlignment(.center)
            .font(.system(.body, design: .rounded))
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .background(cardBackground())
    }

    private func menuField<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .tint(Theme.amber)
            .font(.system(.body, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .background(cardBackground())
    }

    private func selectCard(title: String, subtitle: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? Theme.amber.opacity(0.10) : .white)
                    .shadow(color: Theme.ink.opacity(selected ? 0 : 0.05), radius: 10, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(selected ? Theme.amber : Theme.amberSoft.opacity(0.45),
                                lineWidth: selected ? 2 : 1)))
        }
        .buttonStyle(.plain)
    }

    private func consentToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(Theme.amber)
        .padding(16)
        .background(cardBackground())
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .environmentObject(AccountStore())
}
