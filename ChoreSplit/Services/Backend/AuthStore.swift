import Foundation
import Observation
import AuthenticationServices
import Supabase

/// Who is signed in, and whether they've set up a profile yet.
///
/// There's no separate "sign up": signing in with Google or a phone number for the first time
/// creates the account, and choosing a name and emoji completes it.
@Observable
final class AuthStore {

    enum State: Equatable {
        case loading
        case signedOut
        /// Signed in for the first time — needs a name and emoji before anything else.
        case needsProfile(userID: UUID, suggestedName: String)
        case signedIn(ProfileRow)
    }

    private(set) var state: State = .loading
    private(set) var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private let client: SupabaseClient
    @ObservationIgnored private var listener: Task<Void, Never>?

    init(client: SupabaseClient) {
        self.client = client
    }

    var userID: UUID? {
        switch state {
        case .needsProfile(let id, _): return id
        case .signedIn(let profile):   return profile.id
        default:                       return nil
        }
    }

    // MARK: - Session

    @MainActor
    func start() {
        guard listener == nil else { return }
        listener = Task { @MainActor [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn, .signedOut, .userUpdated, .userDeleted:
                    await self.apply(session)
                default:
                    break
                }
            }
        }
    }

    @MainActor
    private func apply(_ session: Session?) async {
        guard let session else {
            state = .signedOut
            return
        }
        let user = session.user
        do {
            let rows: [ProfileRow] = try await client.from("profiles")
                .select("id,display_name,emoji").eq("id", value: user.id)
                .execute().value
            if let profile = rows.first {
                state = .signedIn(profile)
            } else {
                state = .needsProfile(userID: user.id, suggestedName: Self.suggestedName(from: user))
            }
        } catch {
            // Offline at launch with a saved session: carry on with what we know rather than
            // locking someone out of their own chores.
            if BackendError.isTransient(error), case .signedIn = state { return }
            errorMessage = BackendError.message(for: error)
            if case .loading = state { state = .signedOut }
        }
    }

    private static func suggestedName(from user: User) -> String {
        for key in ["full_name", "name"] {
            if let name = user.userMetadata[key]?.stringValue, !name.isEmpty { return name }
        }
        return ""
    }

    // MARK: - Google

    @MainActor
    func signInWithGoogle() async {
        await perform {
            try await self.client.auth.signInWithOAuth(provider: .google, redirectTo: SupabaseConfig.redirectURL)
        }
    }

    // MARK: - Phone

    /// Text a six-digit code. `phone` must be in international form, e.g. +15551234567.
    @MainActor
    func sendCode(to phone: String) async -> Bool {
        await perform {
            try await self.client.auth.signInWithOTP(phone: phone)
        }
    }

    @MainActor
    func verify(phone: String, code: String) async -> Bool {
        await perform {
            try await self.client.auth.verifyOTP(phone: phone, token: code, type: .sms)
        }
    }

    // MARK: - Profile

    @MainActor
    func saveProfile(name: String, emoji: String) async -> Bool {
        guard let userID else { return false }
        let profile = ProfileRow(id: userID, displayName: name.trimmingCharacters(in: .whitespacesAndNewlines), emoji: emoji)
        let saved = await perform {
            try await self.client.from("profiles").upsert(profile, returning: .minimal).execute()
        }
        if saved { state = .signedIn(profile) }
        return saved
    }

    @MainActor
    func signOut() async {
        _ = await perform {
            try await self.client.auth.signOut()
        }
        state = .signedOut
    }

    // MARK: - Helpers

    /// Runs an auth call, turning failures into a message. Cancelling the Google sheet isn't
    /// an error worth showing.
    @MainActor
    @discardableResult
    private func perform(_ work: @escaping () async throws -> Void) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work()
            return true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return false
        } catch {
            errorMessage = BackendError.message(for: error)
            return false
        }
    }
}
