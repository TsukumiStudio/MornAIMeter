import XCTest
@testable import MornAIMeter

final class CredentialsTests: XCTestCase {
    private func makeRawJSON(accessToken: String, expiry: String?) -> String {
        var token: [String: Any] = [
            "access_token": accessToken,
            "token_type": "Bearer",
            "refresh_token": "fake-refresh-token-abc123",
        ]
        if let expiry {
            token["expiry"] = expiry
        }
        let json: [String: Any] = ["token": token, "auth_method": "consumer"]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return String(data: data, encoding: .utf8)!
    }

    func testParseAntigravityKeychainValueWithBase64Prefix() throws {
        let raw = makeRawJSON(accessToken: "fake-access-token-abc123", expiry: "2026-09-03T20:38:55.163637+09:00")
        let encoded = "go-keyring-base64:" + Data(raw.utf8).base64EncodedString()

        let result = try Credentials.parseAntigravityKeychainValue(encoded)

        XCTAssertEqual(result.accessToken, "fake-access-token-abc123")
        XCTAssertNotNil(result.expiry)
    }

    func testParseAntigravityKeychainValueWithoutPrefix() throws {
        let raw = makeRawJSON(accessToken: "fake-access-token-xyz789", expiry: "2026-09-03T20:38:55.163637+09:00")

        let result = try Credentials.parseAntigravityKeychainValue(raw)

        XCTAssertEqual(result.accessToken, "fake-access-token-xyz789")
        XCTAssertNotNil(result.expiry)
    }

    func testParseAntigravityKeychainValueBrokenBase64Throws() {
        let broken = "go-keyring-base64:not-valid-base64!!!"

        XCTAssertThrowsError(try Credentials.parseAntigravityKeychainValue(broken)) { error in
            guard case .invalidJSON = error as? CredentialError else {
                return XCTFail("invalidJSON を期待したが \(error) だった")
            }
        }
    }

    func testParseAntigravityKeychainValueMissingExpiryReturnsNilExpiry() throws {
        let raw = makeRawJSON(accessToken: "fake-access-token-noexp", expiry: nil)

        let result = try Credentials.parseAntigravityKeychainValue(raw)

        XCTAssertEqual(result.accessToken, "fake-access-token-noexp")
        XCTAssertNil(result.expiry)
    }
}
