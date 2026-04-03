import XCTest
@testable import Laterrr

final class TikTokDescriptionExtractorTests: XCTestCase {
    func testTikTokPlaceParserExtractsOnlyPinnedVenues() {
        let caption = """
        10 must visit cafés in Paris
        📍Le Cristal Bar Brasserie
        📍Carette
        📍Madame Madame
        📍Angelina

        Which one would you visit first? 🤍
        """

        let parsedRoundup = TikTokPlaceParser.parse(description: caption)

        XCTAssertEqual(parsedRoundup.locationHint, "Paris")
        XCTAssertEqual(
            parsedRoundup.venueNames,
            [
                "Le Cristal Bar Brasserie",
                "Carette",
                "Madame Madame",
                "Angelina"
            ]
        )
    }

    func testTikTokPlaceParserReturnsNoVenuesWithoutPins() {
        let caption = """
        10 must visit cafés in Paris
        Le Cristal Bar Brasserie
        Carette
        Madame Madame
        """

        let parsedRoundup = TikTokPlaceParser.parse(description: caption)

        XCTAssertTrue(parsedRoundup.venueNames.isEmpty)
    }

    func testExtractedDescriptionPrefersUniversalDataPayload() {
        let html = #"""
        <html>
        <head>
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">
        {
          "__DEFAULT_SCOPE__": {
            "webapp": {
              "reflow": {
                "video": {
                  "detail": {
                    "itemInfo": {
                      "itemStruct": {
                        "desc": "10 must visit caf\u00e9s in Paris\nLe Cristal Bar Brasserie\nCarette\nMadame Madame"
                      }
                    },
                    "shareMeta": {
                      "desc": "fallback description"
                    }
                  }
                }
              }
            }
          }
        }
        </script>
        <meta property="og:description" content="wrong fallback">
        </head>
        </html>
        """#

        let description = TikTokDescriptionExtractor.extractedDescription(from: html)

        XCTAssertEqual(
            description,
            """
            10 must visit cafés in Paris
            Le Cristal Bar Brasserie
            Carette
            Madame Madame
            """
        )
    }

    func testExtractedDescriptionHandlesMetaTagsWhenContentAppearsFirst() {
        let html = #"""
        <html>
        <head>
        <meta content="Paris café list" property="og:description">
        </head>
        </html>
        """#

        let description = TikTokDescriptionExtractor.extractedDescription(from: html)

        XCTAssertEqual(description, "Paris café list")
    }

    func testExtractedDescriptionPrefersHydratedVisibleTextOverGenericShareShell() {
        let html = #"""
        <html>
        <head>
        <meta property="og:description" content="Watch this video on TikTok. shared a video with you.">
        </head>
        <body></body>
        </html>
        """#

        let visibleText = """
        10 must visit cafés in Paris
        Le Cristal Bar Brasserie
        Carette
        Madame Madame
        Angelina
        """

        let description = TikTokDescriptionExtractor.extractedDescription(
            from: html,
            visibleText: visibleText
        )

        XCTAssertEqual(
            description,
            """
            10 must visit cafés in Paris
            Le Cristal Bar Brasserie
            Carette
            Madame Madame
            Angelina
            """
        )
    }
}
