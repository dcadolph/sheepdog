import Foundation

// SignInRefusal is why a browser sign-in came back refused, sorted by what the user can do next.
public enum SignInRefusal: Sendable, Equatable {
    // userDeclined means the user canceled the consent screen.
    case userDeclined
    // adminApproval means the organization requires an admin to approve Sheepdog first.
    case adminApproval
    // orgBlocked means the organization does not allow outside apps to read its calendars.
    case orgBlocked
    // other is any refusal not listed above, with the provider's error code only.
    case other(code: String)

    // microsoftCodes maps the AADSTS codes Sheepdog recognizes to their refusal.
    private static let microsoftCodes: [String: SignInRefusal] = [
        "65004": .userDeclined,
        "65001": .adminApproval,
        "90094": .adminApproval,
        "90095": .adminApproval,
        "50105": .adminApproval,
        "53003": .orgBlocked,
    ]

    // classify sorts a redirect's error and error_description into a refusal. The description is
    // only searched for codes. It never reaches the message, since it carries trace ids and tenant
    // text.
    public static func classify(kind: AccountKind, error: String, description: String?) -> SignInRefusal {
        switch kind {
        case .microsoft:
            let aadsts = description.flatMap(aadstsCode)
            if let aadsts, let known = microsoftCodes[aadsts] {
                return known
            }
            return .other(code: safeCode(aadsts.map { "AADSTS" + $0 } ?? error))
        case .google:
            let pair = (error + " " + (description ?? "")).lowercased()
            if pair.contains("admin_policy_enforced") {
                return .adminApproval
            }
            if pair.contains("org_internal") {
                return .orgBlocked
            }
            if error == "access_denied" {
                return .userDeclined
            }
            return .other(code: safeCode(error))
        case .icloud, .caldav:
            return .other(code: safeCode(error))
        }
    }

    // message tells the user what happened and what to do next.
    public var message: String {
        switch self {
        case .userDeclined:
            return "You canceled the sign-in. Nothing was connected."
        case .adminApproval:
            return "Your organization needs an admin to approve Sheepdog before it can read your "
                + "calendar. Send your admin the For IT admins page, or add the account in System "
                + "Settings, Internet Accounts, and Sheepdog reads it through macOS Calendar."
        case .orgBlocked:
            return "Your organization doesn't allow outside apps to read its calendars. Add the "
                + "account in System Settings, Internet Accounts, and Sheepdog reads it through "
                + "macOS Calendar, if your organization allows that."
        case .other(let code):
            return "Sign-in was refused (\(code)). Try again, or add the account in Internet "
                + "Accounts."
        }
    }

    // needsOrganization reports a refusal only the organization or Internet Accounts can get past.
    public var needsOrganization: Bool {
        self == .adminApproval || self == .orgBlocked
    }

    // aadstsCode returns the digits of the first AADSTS code in a description.
    private static func aadstsCode(_ description: String) -> String? {
        guard let range = description.range(of: "AADSTS") else {
            return nil
        }
        let digits = description[range.upperBound...].prefix { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    // safeCode keeps a provider error code to letters, digits and underscores, at most 40 of them,
    // so a crafted redirect cannot put a sentence on screen.
    private static func safeCode(_ code: String) -> String {
        let kept = code.unicodeScalars.filter {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_")
        }
        let text = String(String.UnicodeScalarView(kept.prefix(40)))
        return text.isEmpty ? "unknown" : text
    }
}
