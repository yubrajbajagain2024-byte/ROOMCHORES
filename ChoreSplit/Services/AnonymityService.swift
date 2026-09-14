import Foundation
import CryptoKit

/// Keeps ratings unattributable in the UI while still stopping one person voting twice.
///
/// A rating stores a salted SHA-256 of the rater's ID rather than the ID itself. The
/// app can check "has *this* roommate already rated?" by recomputing the hash, but the
/// stored table reads as opaque tokens rather than names.
///
/// This is deliberate obfuscation, not a cryptographic guarantee: anyone with the device,
/// the salt and the short list of household member IDs could brute-force the mapping.
/// The protection that actually matters socially is the reveal threshold — aggregates
/// stay hidden until `Household.minimumRatingsToReveal` ratings are in, so a score can
/// never be traced to a single roommate by elimination.
enum AnonymityService {

    static func newSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    static func token(for roommateID: UUID, salt: Data) -> String {
        var input = salt
        input.append(contentsOf: roommateID.uuidString.utf8)
        let digest = SHA256.hash(data: input)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
