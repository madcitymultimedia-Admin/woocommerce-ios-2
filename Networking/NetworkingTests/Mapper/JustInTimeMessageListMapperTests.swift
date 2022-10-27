import XCTest
@testable import Networking
import TestKit

final class JustInTimeMessageListMapperTests: XCTestCase {
    /// Dummy Site ID.
    ///
    private let dummySiteID: Int64 = 1678

    /// Verifies that the message is parsed.
    ///
    func test_JustInTimeMessageListMapper_parses_the_JustInTimeMessage_in_response() throws {
        let justInTimeMessages = try mapLoadJustInTimeMessageListResponse()
        XCTAssertNotNil(justInTimeMessages)
        assertEqual(1, justInTimeMessages?.count)
    }

    /// Verifies that the fields are all parsed correctly.
    ///
    func test_JustInTimeMessageListMapper_parses_all_fields_in_result() throws {
        // Given, When
        let justInTimeMessage = try XCTUnwrap(mapLoadJustInTimeMessageListResponse()).first

        // Then
        let expectedJustInTimeMessage = JustInTimeMessage(siteID: dummySiteID,
                                                          messageID: "woomobile_ipp_barcode_users",
                                                          featureClass: "woomobile_ipp",
                                                          ttl: 300,
                                                          content: JustInTimeMessage.Content(
                                                            message: "In-person card payments",
                                                            description: "Sell anywhere, and take card payments using a mobile card reader."),
                                                          cta: JustInTimeMessage.CTA(
                                                            message: "Purchase Card Reader",
                                                            link: "https://woocommerce.com/products/hardware/US"))
        assertEqual(expectedJustInTimeMessage, justInTimeMessage)
    }
}


// MARK: - Test Helpers

private extension JustInTimeMessageListMapperTests {
    /// Returns the JustInTimeMessageMapper output upon receiving `filename` (Data Encoded)
    ///
    func mapJustInTimeMessageList(from filename: String) throws -> [JustInTimeMessage]? {
        guard let response = Loader.contentsOf(filename) else {
            return nil
        }

        return try JustInTimeMessageListMapper(siteID: dummySiteID).map(response: response)
    }

    /// Returns the JustInTimeMessageListMapper output from `just-in-time-message-list.json`
    ///
    func mapLoadJustInTimeMessageListResponse() throws -> [JustInTimeMessage]? {
        return try mapJustInTimeMessageList(from: "just-in-time-message-list")
    }
}