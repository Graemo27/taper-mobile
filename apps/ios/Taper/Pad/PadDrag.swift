import CoreGraphics

/// Where a dragged key would land, worked out from how far it has moved.
///
/// The pad's geometry is fixed rather than flexible — `AppLayout` guarantees
/// three keys plus two gaps is exactly the content width — so a drag's target
/// can be arithmetic instead of hit-testing. That is the whole reason this is a
/// value with a function rather than a gesture tangled into the view: the rule
/// somebody wants to argue with is the one below, and it is checkable without
/// rendering anything or touching a screen.
enum PadDrag {
    /// The pad is three keys to a row, fixed by `AppLayout`'s arithmetic.
    static let perRow = 3

    /// One step right is one key plus one gap; one step down is three of them.
    static let step = CGSize(
        width: AppLayout.key + AppLayout.padGap,
        height: AppLayout.key + AppLayout.padGap
    )

    /// The index the key dragged from `origin` should take, given how far it
    /// has been moved and how many keys the ledger holds.
    ///
    /// Rounded rather than truncated, so a key swaps when it is more than
    /// halfway onto its neighbour rather than only once fully clear of it —
    /// the difference between a pad that reorders where the eye expects and
    /// one that needs an extra shove.
    ///
    /// Clamped to the ledger. A drag well past the end lands on the end; the
    /// alternative is a key that vanishes because somebody's thumb kept going.
    static func target(from origin: Int, translation: CGSize, count: Int) -> Int {
        guard count > 0 else { return 0 }
        // Worked out as a column and a row rather than as one number, because
        // a row is only three wide and sideways is not a way down. Added
        // linearly, a drag two seats right from the end of a row walked into
        // the next one — the key changing rows while the finger never left
        // its own. The column is clamped to the row it is in; reaching the
        // row below means dragging down to it, which is where it is.
        let across = Int((translation.width / step.width).rounded())
        let down = Int((translation.height / step.height).rounded())
        let column = min(max(origin % perRow + across, 0), perRow - 1)
        let row = origin / perRow + down
        return min(max(row * perRow + column, 0), count - 1)
    }

    /// The ledger's ids with one moved to a new index.
    ///
    /// Removed then inserted, which is what makes this a *move* rather than a
    /// swap: dragging the first key to the end should slide the rest up by one,
    /// not trade places with whatever happened to be last.
    static func reordered(_ ids: [Int], moving id: Int, to index: Int) -> [Int] {
        guard let from = ids.firstIndex(of: id) else { return ids }
        var moved = ids
        moved.remove(at: from)
        moved.insert(id, at: min(max(index, 0), moved.count))
        return moved
    }
}
