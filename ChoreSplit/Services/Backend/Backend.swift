import Foundation
import Supabase

/// The project's Supabase URL and key, read from `Supabase.plist` in the app bundle.
struct SupabaseConfig {
    let url: URL
    let anonKey: String

    /// Where Google sign-in hands control back to the app.
    static let redirectURL = URL(string: "choresplit://login-callback")!

    static func load(from bundle: Bundle = .main) -> SupabaseConfig? {
        guard let fileURL = bundle.url(forResource: "Supabase", withExtension: "plist"),
              let data = try? Data(contentsOf: fileURL),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let rawURL = values["SupabaseURL"] as? String,
              let key = values["SupabaseAnonKey"] as? String,
              let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https",
              !rawURL.contains("YOUR-PROJECT-REF"),
              !key.isEmpty, !key.hasPrefix("YOUR-")
        else { return nil }
        return SupabaseConfig(url: url, anonKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// The one Supabase client, or `nil` when the app hasn't been pointed at a project yet.
enum Backend {
    static let config = SupabaseConfig.load()

    static let client: SupabaseClient? = config.map { config in
        SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: SupabaseConfig.redirectURL,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    static var isConfigured: Bool { client != nil }

    static let proofVideoBucket = "proof-videos"

    /// Where a task's proof video lives in storage: "<group id>/<assignment id>.mp4". The
    /// storage rules read the group id from the first folder.
    static func proofVideoPath(groupID: UUID, assignmentID: UUID) -> String {
        "\(groupID.uuidString.lowercased())/\(assignmentID.uuidString.lowercased()).mp4"
    }
}

typealias SupabaseClientType = SupabaseClient

/// Turns backend errors into something worth showing a person.
enum BackendError {
    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "The server took too long to answer. Try again."
            default:
                return "Couldn't reach the server. Try again."
            }
        }
        if let postgrest = error as? PostgrestError {
            // Messages raised by the database functions are already written for people.
            return postgrest.message.prefix(1).uppercased() + postgrest.message.dropFirst()
        }
        if let auth = error as? AuthError {
            return auth.message
        }
        return error.localizedDescription
    }

    /// Network trouble is worth retrying; a refusal from the server isn't.
    static func isTransient(_ error: Error) -> Bool {
        if error is URLError { return true }
        if error is CancellationError { return true }
        return false
    }
}

extension PostgrestError: RefusalCoded {
    var refusalCode: String? { code }
}
