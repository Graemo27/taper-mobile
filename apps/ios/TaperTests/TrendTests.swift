import Foundation
import Testing
@testable import Taper

/// Covers the graph's three claims: the bars, the verdict, and the sentence.
struct TrendTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A run of days ending today, oldest first, from parallel arrays.
    private func days(logged: [Double], caps: [Double?]) -> ([DayRollup], Date) {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let rollups = logged.enumerated().map { index, mg in
            let day = calendar.date(byAdding: .day, value: index - (logged.count - 1), to: today)!
            let entry = StoredCheckIn(
                id: index + 1, ledger: .source, label: "Pouches", form: .pouch,
                mg: mg, quantity: 1,
                loggedOn: PlanDay.wireFormat(day, timeZone: calendar.timeZone),
                createdAt: day
            )
            return DayRollup(day: day, entries: mg > 0 ? [entry] : [], capMg: caps[index])
        }
        return (rollups, today)
    }

    private func trend(logged: [Double], caps: [Double?]) -> Trend {
        let (rollups, today) = days(logged: logged, caps: caps)
        return Trend(days: rollups, calendar: calendar, today: today)
    }

    @Test("bars and cap line share one scale")
    func anOverCapDayDrawsOverItsCap() {
        // The one relationship this chart exists to show. Scaled apart, an
        // over-cap day would sit under its own ceiling.
        let trend = trend(logged: [16, 8], caps: [12, 12])

        let over = trend.bars[0]
        let under = trend.bars[1]
        #expect(over.fraction == 1, "the tallest thing on the chart is not full height")
        #expect(over.capFraction == 0.75)
        #expect(over.fraction > over.capFraction!, "an over-cap day drew under its cap")
        #expect(under.fraction < under.capFraction!)

        // The other direction, and the one that actually catches a split
        // scale: when the cap is the tallest thing on the chart, a bar-only
        // scale pushes the cap line past the top edge. The first draft of this
        // test only measured days whose bars out-topped their caps, and the
        // split-scale mutation returned identical numbers for all of them.
        let capped = self.trend(logged: [3, 8], caps: [12, 12])
        #expect(capped.bars[0].capFraction == 1, "the tallest cap is not the top of the chart")
        #expect(capped.bars[1].fraction == 8.0 / 12.0)
    }

    @Test("a day no plan covered has no cap segment, not a segment at zero")
    func nilIsNotZero() {
        let trend = trend(logged: [3, 3], caps: [nil, 12])

        #expect(trend.bars[0].capFraction == nil)
        #expect(trend.bars[1].capFraction != nil)
    }

    @Test("the quit week's cap of zero is a line at the floor, not a missing one")
    func zeroIsNotNil() {
        // The sibling of the test above, from the other side: a cap of zero is
        // a real ceiling — the whole point of the taper — and dropping its
        // segment would erase the goal from the week it is reached.
        let trend = trend(logged: [0, 0], caps: [0, 0])

        #expect(trend.bars.allSatisfy { $0.capFraction == 0 })
    }

    @Test("only the last bar is today")
    func todayIsDrawnFilled() {
        let trend = trend(logged: [3, 3, 3], caps: [12, 12, 12])

        #expect(trend.bars.map(\.isToday) == [false, false, true])
    }

    @Test("the verdict follows the shape, not the wish")
    func trendingDownIsEarned() {
        #expect(self.trend(logged: [12, 10, 8, 6, 5, 4, 3],
                           caps: Array(repeating: 12, count: 7)).headline == "Trending down")
        #expect(self.trend(logged: [3, 4, 5, 6, 8, 10, 12],
                           caps: Array(repeating: 12, count: 7)).headline == "Trending up")
        #expect(self.trend(logged: [6, 6, 6, 6, 6, 6, 6],
                           caps: Array(repeating: 12, count: 7)).headline == "Holding steady")
        #expect(self.trend(logged: [0, 0, 0, 0, 0, 0, 0],
                           caps: Array(repeating: 12, count: 7)).headline == "Nothing logged yet")
    }

    @Test("the sentence counts only days a cap covered")
    func aDayWithNoCeilingCannotBeUnderOne() {
        let trend = trend(logged: [3, 3, 3], caps: [nil, 12, 12])

        #expect(trend.caption == "Dotted line is your daily cap, stepping down. 2 of 2 days under — the shape is working.")
    }

    @Test("the shape is only said to be working when it mostly is")
    func theCaptionDoesNotFlatter() {
        let struggling = trend(logged: [16, 16, 16, 3], caps: [12, 12, 12, 12])

        #expect(struggling.caption == "Dotted line is your daily cap, stepping down. 1 of 4 days under.")
    }

    @Test("an empty run is not evidence that the shape is working")
    func zeroObservationsMakeNoClaim() {
        // Every capped zero-day counts as under, so a week with nothing
        // logged would claim 7 of 7 and success — beside a heading that says
        // nothing was logged.
        let empty = trend(logged: [0, 0, 0], caps: [12, 12, 12])

        #expect(empty.caption
                == "Dotted line is your daily cap, stepping down. Nothing logged against it yet.")
        #expect(!empty.caption.contains("working"), "an empty week flattered itself")
    }

    @Test("the working claim rests on days with something logged")
    func blanksAroundAnOverCapDayDoNotFlatter() {
        // CodeRabbit's case on the empty-run guard: [0, 0, 16] against caps
        // of 12. The count believes the record — two days under — but the
        // only day with evidence is over, and "the shape is working" on that
        // week would be the app flattering a claim its own observations
        // refute. Late-taper zero days still earn it, because there the
        // observed days are under too.
        let mixed = trend(logged: [0, 0, 16], caps: [12, 12, 12])
        #expect(mixed.caption == "Dotted line is your daily cap, stepping down. 2 of 3 days under.")
        #expect(!mixed.caption.contains("working"))

        let lateTaper = trend(logged: [0, 0, 2], caps: [1, 1, 12])
        #expect(lateTaper.caption.contains("3 of 3 days under — the shape is working."),
                "a genuinely clean late-taper week lost its own evidence")
    }

    @Test("a run before any plan says so instead of counting nothing")
    func noCapIsItsOwnSentence() {
        #expect(trend(logged: [3, 3], caps: [nil, nil]).caption
                == "Dotted line is your daily cap. No cap covered these days.")
    }

    @Test("the letters under the bars are the days they are")
    func weekdayLettersComeFromTheCalendar() {
        let trend = trend(logged: Array(repeating: 3, count: 7),
                          caps: Array(repeating: nil, count: 7))

        // The anchor is a Thursday, so the week ending on it reads F S S M T
        // W T. Pinned rather than recomputed — a test that derives the letters
        // the way the code does would pass whatever both got wrong.
        #expect(trend.bars.map(\.label) == ["F", "S", "S", "M", "T", "W", "T"])
    }
}
