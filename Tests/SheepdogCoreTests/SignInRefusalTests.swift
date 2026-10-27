import Foundation
import Testing

@testable import SheepdogCore

// RefusalCase is one refused redirect and the refusal it should sort into.
struct RefusalCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Kind is the service that refused.
    let kind: AccountKind
    // Error is the redirect's error parameter.
    let error: String
    // Description is the redirect's error_description parameter.
    let description: String?
    // Want is the expected refusal.
    let want: SignInRefusal

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// refusalTrace is the tenant text a Microsoft description carries after the code.
let refusalTrace = ": The user or administrator has not consented."
    + " Trace ID: 7f3e Correlation ID: 91aa"

// refusalCases covers every code the classifier names plus unknown ones.
let refusalCases: [RefusalCase] = [
    RefusalCase( // Test 0: The user declined Microsoft's consent screen.
        name: "65004", kind: .microsoft, error: "access_denied",
        description: "AADSTS65004" + refusalTrace, want: .userDeclined
    ),
    RefusalCase( // Test 1: The tenant needs admin consent.
        name: "65001", kind: .microsoft, error: "consent_required",
        description: "AADSTS65001" + refusalTrace, want: .adminApproval
    ),
    RefusalCase( // Test 2: The admin consent request was sent but not approved.
        name: "90094", kind: .microsoft, error: "access_denied",
        description: "AADSTS90094" + refusalTrace, want: .adminApproval
    ),
    RefusalCase( // Test 3: The admin consent workflow is pending.
        name: "90095", kind: .microsoft, error: "access_denied",
        description: "AADSTS90095" + refusalTrace, want: .adminApproval
    ),
    RefusalCase( // Test 4: The user is not assigned to the app.
        name: "50105", kind: .microsoft, error: "access_denied",
        description: "AADSTS50105" + refusalTrace, want: .adminApproval
    ),
    RefusalCase( // Test 5: Conditional Access blocked the sign-in.
        name: "53003", kind: .microsoft, error: "access_denied",
        description: "AADSTS53003" + refusalTrace, want: .orgBlocked
    ),
    RefusalCase( // Test 6: The code sits mid-sentence.
        name: "65001 mid-sentence", kind: .microsoft, error: "invalid_request",
        description: "Error AADSTS65001 occurred", want: .adminApproval
    ),
    RefusalCase( // Test 7: An unknown Microsoft code keeps the code only.
        name: "unknown aadsts", kind: .microsoft, error: "invalid_request",
        description: "AADSTS700016" + refusalTrace, want: .other(code: "AADSTS700016")
    ),
    RefusalCase( // Test 8: A Microsoft refusal with no code keeps the error.
        name: "microsoft no code", kind: .microsoft, error: "server_error",
        description: "Something broke" + refusalTrace, want: .other(code: "server_error")
    ),
    RefusalCase( // Test 9: A crafted error is cut down to a safe code.
        name: "crafted error", kind: .google, error: "Call 555-0100 now!",
        description: nil, want: .other(code: "Call5550100now")
    ),
    RefusalCase( // Test 10: The Google user pressed Cancel.
        name: "google declined", kind: .google, error: "access_denied",
        description: nil, want: .userDeclined
    ),
    RefusalCase( // Test 11: The Workspace admin blocked the app.
        name: "google admin policy", kind: .google, error: "access_denied",
        description: "admin_policy_enforced", want: .adminApproval
    ),
    RefusalCase( // Test 12: The app is internal to another organization.
        name: "google org internal", kind: .google, error: "org_internal",
        description: nil, want: .orgBlocked
    ),
    RefusalCase( // Test 13: An unknown Google error keeps the code only.
        name: "google unknown", kind: .google, error: "invalid_scope",
        description: "Some scope text", want: .other(code: "invalid_scope")
    ),
    RefusalCase( // Test 14: A password service never classifies as a consent refusal.
        name: "caldav", kind: .caldav, error: "access_denied",
        description: "AADSTS65001", want: .other(code: "access_denied")
    ),
    RefusalCase( // Test 15: An empty error still yields a code.
        name: "empty", kind: .google, error: "",
        description: nil, want: .other(code: "unknown")
    ),
]

// testSignInRefusalClassify checks each refusal sorts into its case and never shows the
// description.
@Test(arguments: refusalCases)
func testSignInRefusalClassify(test: RefusalCase) {
    let got = SignInRefusal.classify(
        kind: test.kind, error: test.error, description: test.description
    )
    #expect(got == test.want)
    if let description = test.description, case .other(let code) = got {
        #expect(got.message.contains(code))
        #expect(!got.message.contains(description))
        #expect(!got.message.contains("Trace ID"))
    }
}

// testSignInRefusalMessage checks each case names a next step and only organization refusals offer
// the admins page.
@Test func testSignInRefusalMessage() {
    let declined = "You canceled the sign-in. Nothing was connected."
    #expect(SignInRefusal.userDeclined.message == declined)
    #expect(SignInRefusal.adminApproval.message.contains("For IT admins"))
    #expect(SignInRefusal.orgBlocked.message.contains("Internet Accounts"))
    #expect(SignInRefusal.other(code: "x1").message.hasPrefix("Sign-in was refused (x1)."))
    #expect(SignInRefusal.adminApproval.needsOrganization)
    #expect(SignInRefusal.orgBlocked.needsOrganization)
    #expect(!SignInRefusal.userDeclined.needsOrganization)
    #expect(!SignInRefusal.other(code: "x1").needsOrganization)
}
