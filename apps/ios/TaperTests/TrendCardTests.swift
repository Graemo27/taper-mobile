import Foundation
import Testing
@testable import Taper

private final class RefusingDays: CheckInReading, @unchecked Sendable {
    func entries(from first: Date, to last: Date) async throws -> [StoredCheckIn] {
        throw URLError(.notConnectedToInternet)
    }
}
private final class EmptyVersions: PlanVersionReading, @unchecked Sendable {
    func versions() async throws -> [StoredPlanVersion] { [] }
}

/// Covers what the graph card says around the chart — the words are decisions,
/// and the chart itself is `Trend`'s, already pinned.
@MainActor
struct TrendCardTests {
    @Test("the apology outranks the caption, and loading is not an apology")
    func theCaptionSaysWhatIsActuallyKnown() async {
        let unread = TrendRecord(checkIns: nil, plans: nil)
        #expect(TrendCard(record: unread).captionText == "Reading the week…")

        let failed = TrendRecord(checkIns: RefusingDays(), plans: EmptyVersions())
        await failed.load()
        #expect(TrendCard(record: failed).captionText
                == "Couldn't load the week. Check your connection and try again.")
    }

    @Test("the chart speaks its verdict and its count")
    func voiceOverGetsTheClaims() {
        // The heading's verdict and the caption's count are the card's two
        // claims, and neither reaches VoiceOver off a Canvas — a chart is the
        // one view with nothing readable in it unless it is said here.
        let record = TrendRecord(checkIns: nil, plans: nil)
        #expect(TrendCard(record: record).spokenChart == "Nicotine over time, loading")
    }
}
