import Foundation

/// What is chosen on the pad but not yet logged.
///
/// One key at a time. The board reads a selection back as a single "Pouch × 1"
/// above a single figure, and a pad that quietly accumulated two different keys
/// would show a total nobody could account for.
@Observable
@MainActor
final class PadSelection {
    private(set) var pending: PendingEntry?

    init() {}

    /// A tap on a key.
    ///
    /// The same key again counts one more of it rather than starting over,
    /// which is what the board's "× 1" is counting — three pouches are three
    /// taps and one trip through the action bar, not three trips.
    ///
    /// A different key replaces the selection instead of joining it, for the
    /// reason above: the readout names one thing.
    func tap(_ key: StoredPadKey) {
        guard let current = pending, current.key.id == key.id else {
            pending = PendingEntry(key: key)
            return
        }
        // `PendingEntry` clamps at the column's ceiling, so counting past 20
        // holds there rather than building a number the insert would refuse
        // after the user believes they have logged it.
        pending = PendingEntry(key: key, quantity: current.quantity + 1)
    }

    /// Puts the pad back to resting.
    func clear() { pending = nil }
}
