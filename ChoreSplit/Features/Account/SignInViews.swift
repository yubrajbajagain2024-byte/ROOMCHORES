import SwiftUI

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AuthStore.self) private var auth
    @State private var showingPhone = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Wordmark(size: 46)
                Text("Split the chores.\nKeep it fair.")
                    .font(.system(size: 30, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Every chore is worth points. Roommates rate each other's work anonymously, and whoever's behind gets the next job.")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(spacing: 12) {
                SecondaryButton(title: "Continue with Google", isEnabled: !auth.isWorking) {
                    Task { await auth.signInWithGoogle() }
                } icon: {
                    GoogleGlyph()
                }

                PrimaryButton(title: "Continue with phone number", systemImage: "phone.fill", isEnabled: !auth.isWorking) {
                    showingPhone = true
                }

                ErrorText(message: auth.errorMessage)

                Text("New here? Either option creates your account.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(Theme.feedCard.ignoresSafeArea())
        .sheet(isPresented: $showingPhone) {
            PhoneSignInView()
        }
    }
}

// MARK: - Phone

struct PhoneSignInView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private enum Step { case number, code }

    @State private var step: Step = .number
    @State private var country = CallingCode.default
    @State private var number = ""
    @State private var code = ""
    @State private var resendAvailableAt = Date()
    @State private var now = Date()
    @FocusState private var focused: Bool

    private var e164: String { country.dial + CallingCode.nationalDigits(number) }
    private var numberLooksValid: Bool { (6...14).contains(CallingCode.nationalDigits(number).count) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                switch step {
                case .number: numberStep
                case .code:   codeStep
                }
                Spacer()
            }
            .padding(24)
            .background(Theme.feedCard.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
            .task {
                while !Task.isCancelled {
                    now = Date()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private var numberStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What's your number?")
                .font(.system(size: 28, weight: .bold))
            Text("We'll text you a 6-digit code. Message rates may apply.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondaryText)

            HStack(spacing: 10) {
                Menu {
                    Picker("Country", selection: $country) {
                        ForEach(CallingCode.all) { option in
                            Text("\(option.flag)  \(option.name) \(option.dial)").tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(country.flag)
                        Text(country.dial).foregroundStyle(.primary)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    }
                    .font(.system(size: 18))
                    .padding(.horizontal, 14)
                    .frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chipFill))
                }

                PillField {
                    TextField("Phone number", text: $number)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($focused)
                }
            }

            ErrorText(message: auth.errorMessage)

            PrimaryButton(title: "Send code", isWorking: auth.isWorking, isEnabled: numberLooksValid) {
                Task {
                    if await auth.sendCode(to: e164) {
                        code = ""
                        resendAvailableAt = Date().addingTimeInterval(30)
                        withAnimation { step = .code }
                        focused = true
                    }
                }
            }
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Enter the code")
                .font(.system(size: 28, weight: .bold))
            Text("Sent to \(country.dial) \(CallingCode.nationalDigits(number)).")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondaryText)

            PillField {
                TextField("123456", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .tracking(8)
                    .focused($focused)
                    .onChange(of: code) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(6))
                        if digits != value { code = digits }
                        if digits.count == 6 { verify() }
                    }
            }

            ErrorText(message: auth.errorMessage)

            PrimaryButton(title: "Verify", isWorking: auth.isWorking, isEnabled: code.count == 6) {
                verify()
            }

            HStack {
                Button("Change number") {
                    withAnimation { step = .number }
                }
                Spacer()
                let wait = Int(resendAvailableAt.timeIntervalSince(now).rounded(.up))
                Button(wait > 0 ? "Resend in \(wait)s" : "Resend code") {
                    Task {
                        if await auth.sendCode(to: e164) {
                            resendAvailableAt = Date().addingTimeInterval(30)
                        }
                    }
                }
                .disabled(wait > 0 || auth.isWorking)
            }
            .font(.system(size: 15, weight: .medium))
            .tint(Theme.brand)
        }
    }

    private func verify() {
        guard !auth.isWorking else { return }
        Task {
            if await auth.verify(phone: e164, code: code) {
                dismiss()
            }
        }
    }
}

/// International dialling codes for the phone sign-in screen.
struct CallingCode: Identifiable, Hashable {
    let region: String
    let name: String
    let dial: String

    var id: String { region }

    var flag: String {
        region.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }

    static let all: [CallingCode] = [
        ("US", "United States", "+1"), ("CA", "Canada", "+1"), ("GB", "United Kingdom", "+44"),
        ("IE", "Ireland", "+353"), ("AU", "Australia", "+61"), ("NZ", "New Zealand", "+64"),
        ("IN", "India", "+91"), ("NP", "Nepal", "+977"), ("BD", "Bangladesh", "+880"),
        ("PK", "Pakistan", "+92"), ("PH", "Philippines", "+63"), ("SG", "Singapore", "+65"),
        ("AE", "United Arab Emirates", "+971"), ("DE", "Germany", "+49"), ("FR", "France", "+33"),
        ("ES", "Spain", "+34"), ("IT", "Italy", "+39"), ("NL", "Netherlands", "+31"),
        ("BR", "Brazil", "+55"), ("MX", "Mexico", "+52"), ("JP", "Japan", "+81"),
        ("KR", "South Korea", "+82"), ("NG", "Nigeria", "+234"), ("ZA", "South Africa", "+27")
    ].map { CallingCode(region: $0.0, name: $0.1, dial: $0.2) }

    static var `default`: CallingCode {
        let region = Locale.current.region?.identifier ?? "US"
        return all.first { $0.region == region } ?? all[0]
    }

    /// Digits only, without the trunk "0" many countries put in front of local numbers.
    static func nationalDigits(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)
        while digits.hasPrefix("0") { digits.removeFirst() }
        return digits
    }
}

// MARK: - Profile

struct ProfileSetupView: View {
    @Environment(AuthStore.self) private var auth
    let suggestedName: String

    @State private var name = ""
    @State private var emoji = EmojiPickerView.suggestions.randomElement() ?? "🙂"
    @FocusState private var nameFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Wordmark(size: 26)
                    .padding(.top, 8)

                Text("What should your roommates call you?")
                    .font(.system(size: 28, weight: .bold))

                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Theme.memberColor(0).gradient)
                        Text(emoji).font(.system(size: 34))
                    }
                    .frame(width: 64, height: 64)

                    PillField {
                        TextField("Your name", text: $name)
                            .textContentType(.givenName)
                            .focused($nameFocused)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Pick an emoji")
                        .font(.system(size: 15, weight: .semibold))
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(EmojiPickerView.suggestions, id: \.self) { option in
                            Button {
                                emoji = option
                            } label: {
                                Text(option)
                                    .font(.system(size: 26))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(option == emoji ? Theme.brand.opacity(0.18) : Theme.chipFill)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ErrorText(message: auth.errorMessage)

                PrimaryButton(title: "Continue", isWorking: auth.isWorking,
                              isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                    Task { _ = await auth.saveProfile(name: name, emoji: emoji) }
                }

                Button("Use a different account") {
                    Task { await auth.signOut() }
                }
                .font(.system(size: 15))
                .tint(Theme.brand)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.feedCard.ignoresSafeArea())
        .onAppear {
            if name.isEmpty { name = suggestedName }
            nameFocused = name.isEmpty
        }
    }
}

// MARK: - Loading and setup

struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Wordmark(size: 40)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.feedCard.ignoresSafeArea())
    }
}

/// Shown when the app hasn't been given a Supabase project. Aimed at whoever is building the
/// app, not at roommates — a release build always ships with a project configured.
struct BackendSetupView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Wordmark(size: 32)
                Text("Connect a Supabase project")
                    .font(.system(size: 26, weight: .bold))
                Text("Accounts, groups and invites run on Supabase. Until the app has a project to talk to, there's nothing to sign in to.")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)

                VStack(alignment: .leading, spacing: 14) {
                    step(1, "Create a free project at supabase.com.")
                    step(2, "In the SQL editor, run supabase/migrations/20260914000000_choresplit.sql.")
                    step(3, "Copy Config/Supabase.example.plist to ChoreSplit/Supabase.plist and fill in the project URL and anon key.")
                    step(4, "Turn on the Google and Phone providers under Authentication, and add choresplit://login-callback as a redirect URL.")
                    step(5, "Rebuild the app.")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chipFill))

                Text("The README walks through each step.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)

                #if DEBUG
                SecondaryButton(title: "Try the on-device demo instead") {
                    appState.isDemoMode = true
                } icon: {
                    Image(systemName: "iphone")
                }
                .padding(.top, 8)
                #endif
            }
            .padding(24)
        }
        .background(Theme.feedCard.ignoresSafeArea())
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.brand))
            Text(text)
                .font(.system(size: 15))
        }
    }
}
