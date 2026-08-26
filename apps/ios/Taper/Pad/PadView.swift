import SwiftUI

/// L3 — the pad, drawn.
///
/// Two sections in the board's order, treatment above what you are quitting,
/// with the keys three to a row, a meter above and the two actions below.
///
/// The screen owns no state of its own. Every figure comes off the record and
/// every tap goes back to it, so what is on screen and what would be written
/// cannot drift apart.
struct PadView: View {
    let status: PadStatus
    /// Today: the entries, the selection, and writing them.
    @Bindable var record: TodayRecord
    /// The cap the day is measured against, off the plan. Passed rather than
    /// held, because the pad draws the plan's number and does not own it.
    let ceilingMg: Double
    /// The catalogue search, when the pad is showing it instead of its keys.
    @Bindable var search: TreatmentSearchRecord
    /// Whether the pad is searching rather than resting.
    @Binding var isSearching: Bool
    /// The key being made from a search result, when there is one. Held by the
    /// tabs rather than here so a half-filled draft survives a glance at the
    /// plan, the same bargain the search query makes.
    @Binding var draft: NewKeyDraft?
    /// Makes a draft for a chosen product. Passed in because the pad has no
    /// store of its own — it is handed what it draws.
    let draftFor: (NRTResult) -> NewKeyDraft
    /// The source key being typed, when there is one. Held by the tabs rather
    /// than here so a half-answered form survives a glance at the plan, the
    /// same bargain the search query makes.
    @Binding var sourceDraft: NewSourceDraft?
    /// Makes a blank source draft. The pad has no store of its own.
    let newSourceDraft: () -> NewSourceDraft
    /// A key the server confirmed. Handed over rather than reloaded for: the
    /// row is authoritative, and a read would be dropped if another were
    /// already running.
    let onKeyAdded: (StoredPadKey) -> Void
    /// Editing: which keys are going, and whether the pad is in the mode at
    /// all. Held by the tabs so a long-press does not lose its mode to a
    /// glance at the plan.
    @Bindable var edit: PadEditRecord
    /// A removal that finished, whether or not it worked: the id when the
    /// server confirmed it, nil when it did not.
    ///
    /// Nil is reported rather than swallowed because it does not mean the key
    /// survived. A transport error after the delete committed leaves the key
    /// gone on the server and still drawn here — and every retry then fails
    /// too, because the row it is trying to remove is already missing.
    let onKeyRemoved: (Int?) -> Void

    private var tally: TodaysTally { record.tally(ceilingMg: ceilingMg) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lPlus) {
            // The meter goes while editing. It reports a day being logged, and
            // nothing here logs anything — leaving it up would put a live
            // number above a screen that cannot change it.
            if edit.isEditing {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Edit pad")
                        .font(AppFont.display(AppSize.title))
                        .foregroundStyle(AppColor.ink)
                    Text(Self.editHint)
                        .font(AppFont.text(AppSize.body))
                        .foregroundStyle(AppColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                CapMeter(tally: tally, pending: record.selection.pending)
            }

            if let sourceDraft {
                NewSourceKeyView(draft: sourceDraft) {
                    self.sourceDraft = nil
                } onSaved: { stored in
                    // The same ownership check the treatment form needs: a save
                    // is not cancelled with the view that started it.
                    if self.sourceDraft === sourceDraft { self.sourceDraft = nil }
                    onKeyAdded(stored)
                }
            } else if let draft {
                NewTreatmentKeyView(draft: draft) {
                    // Back to the results, not out of the search: somebody who
                    // opened the wrong product is one tap from the right one,
                    // and their query is still in the field.
                    self.draft = nil
                } onSaved: { stored in
                    // Only if this is still the draft on screen. A save is not
                    // cancelled with the view that started it, so cancelling
                    // mid-flight and opening another leaves the first write to
                    // land and reset a search that had moved on.
                    if self.draft === draft {
                        self.draft = nil
                        search.clear()
                        isSearching = false
                    }
                    // Shown either way, because the key was written whoever is
                    // looking at what now.
                    onKeyAdded(stored)
                }
            } else if isSearching {
                TreatmentSearchView(record: search) {
                    search.clear()
                    isSearching = false
                } onPick: { product in
                    draft = draftFor(product)
                }
            } else {
                // The keys scroll and the meter and the actions do not, which
                // is how the board draws L3g. The pad only ever held what
                // onboarding seeded until the two add tiles landed — since then
                // it can grow past the screen, and with no scrolling the keys
                // and the button the whole screen exists for went off the
                // bottom with no way to reach them.
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lPlus) {
                        switch status {
                        case .loading:
                            loading
                        case let .ready(pad):
                            // The sections draw either way. An empty pad is the
                            // one state that most needs the tiles that fill it,
                            // and hiding them left the only way out of it
                            // unreachable.
                            if pad.isEmpty { Text(Self.emptyNote).modifier(EmptyNoteStyle()) }
                            section("YOUR TREATMENT", note: nil,
                                    keys: pad.treatment, canAdd: .treatment)
                            section(
                                "WHAT YOU'RE QUITTING",
                                note: "counts toward the ceiling",
                                keys: pad.sources,
                                canAdd: .source
                            )
                            if let end = Self.endOfPad(pad) {
                                Text(end)
                                    .font(AppFont.text(AppSize.caption))
                                    .foregroundStyle(AppColor.inkFaint)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        case let .unavailable(message):
                            unavailable(message)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Bounded, or a `ScrollView` in a `VStack` takes its content
                // height and nothing is constrained at all — the lesson the
                // search results cost.
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity)
            }

            // The question comes before the button it is about, and the failure
            // after the button that caused it. Both sit directly above the
            // actions rather than at the top: they are about the tap that is
            // happening now, and a message off screen is a message nobody
            // reads.
            if !edit.isEditing, let question = tally.questionBeforeLogging {
                note(question, tone: AppColor.cautionInk)
            }
            if !edit.isEditing, let failure = record.writeFailure {
                note(failure, tone: AppColor.over)
            }
            if let failed = edit.failure { note(failed.message, tone: AppColor.over) }

            if edit.isEditing {
                doneButton
            } else {
                PadActionBar(
                    title: record.checkInTitle,
                    isEnabled: record.canCheckIn,
                    onClear: record.clear,
                    onCheckIn: { Task { await record.checkIn() } }
                )
            }
        }
        .padding(.horizontal, AppLayout.gutter)
        .padding(.top, AppSpacing.lPlus)
        .padding(.bottom, AppSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
    }

    /// One ledger: its eyebrow, then its keys.
    ///
    /// A section with no keys is dropped rather than drawn empty. Somebody who
    /// declined a treatment has no treatment ledger, and a headed but empty
    /// section would read as something failing to load.
    @ViewBuilder
    private func section(
        _ title: String, note: String?, keys: [StoredPadKey], canAdd: PadKey.Ledger? = nil
    ) -> some View {
        if !keys.isEmpty || canAdd != nil {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text(title)
                        .font(AppFont.text(AppSize.nano, .medium))
                        .tracking(AppTracking.eyebrowWide(AppSize.nano))
                        .foregroundStyle(AppColor.inkMuted)
                    if let note {
                        // The one place the app says which ledger the cap
                        // counts. It belongs on the section rather than on each
                        // key, because it is true of the group.
                        Text(note)
                            .font(AppFont.text(AppSize.nano))
                            .foregroundStyle(AppColor.inkFaint)
                    }
                }
                .accessibilityElement(children: .combine)

                rows(of: keys, canAdd: canAdd)
            }
        }
    }

    /// Three to a row, laid out by hand rather than by a grid.
    ///
    /// `AppLayout` fixes the arithmetic — three keys plus two gaps is exactly
    /// the content width — so a flexible grid would only be free to disagree
    /// with it. The last row is left-aligned by padding it out, which keeps a
    /// row of one key under the first key above it rather than centred.
    private func rows(of keys: [StoredPadKey], canAdd: PadKey.Ledger?) -> some View {
        // The add tile rides at the end of the run, so it lands wherever the
        // last key leaves off rather than claiming a row of its own.
        let slots = keys.count + (canAdd == nil ? 0 : 1)
        let chunks = stride(from: 0, to: slots, by: 3).map { start in
            Array(start..<min(start + 3, slots))
        }
        return VStack(alignment: .leading, spacing: AppLayout.padGap) {
            ForEach(chunks, id: \.first) { row in
                HStack(spacing: AppLayout.padGap) {
                    ForEach(row, id: \.self) { slot in
                        if slot < keys.count {
                            let key = keys[slot]
                            PadKeyTile(
                                key: key,
                                // Ignored while editing, which is also what
                                // stops a long press queueing a check-in: the
                                // gesture sets the mode at half a second and
                                // the button's own tap arrives afterwards, on
                                // touch-up, to find it already set.
                                onTap: { if !edit.isEditing { record.selection.tap(key) } },
                                onRemove: edit.isEditing ? {
                                    Task { onKeyRemoved(await edit.remove(key.id)) }
                                } : nil,
                                isRemoving: edit.isRemoving(key.id)
                            )
                            // The way in, as the board names it: a long press
                            // rather than a chrome control, because the pad's
                            // whole surface is keys and a button for editing
                            // would cost one of them.
                            //
                            // Simultaneous, because a `Button` consumes
                            // `onLongPressGesture` outright — the press never
                            // reached it. That means the tap fires too, so
                            // entering the mode clears the selection it just
                            // made: a pad being edited cannot check in, and a
                            // pending tap left behind would be waiting on the
                            // other side of Done.
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                    record.selection.clear()
                                    edit.startEditing()
                                }
                            )
                        } else if canAdd == .treatment {
                            AddKeyTile.treatment { isSearching = true }
                        } else {
                            AddKeyTile.source { sourceDraft = newSourceDraft() }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// A line about the tap in hand, above the actions.
    private func note(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(tone)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var loading: some View {
        HStack(spacing: AppSpacing.m) {
            ProgressView().tint(AppColor.ink)
            Text("Loading your pad…")
                .font(AppFont.text(AppSize.body))
                .foregroundStyle(AppColor.inkMuted)
        }
    }

    /// A pad with nothing on it.
    ///
    /// Reachable by anyone whose plan was saved before the pad was seeded, and
    /// by anyone whose seed failed. It says what is missing rather than showing
    /// a blank area, because a screen that is silently empty reads as broken.
    /// Leaves edit mode, once nothing is still going.
    private var doneButton: some View {
        Button { edit.finishEditing() } label: {
            Text("Done")
                .font(AppFont.text(AppSize.bodyLarge, .medium))
                .foregroundStyle(AppColor.inkInverse)
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.action)
                .background(edit.canFinish ? AppColor.ink : AppColor.inkFaint, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!edit.canFinish)
        .padding(.top, AppSpacing.m)
        .accessibilityIdentifier("pad.doneEditing")
    }

    /// How the board says the two edits work, in the order they are reachable.
    ///
    /// Reordering is not built yet, so the hint names only what is. A line
    /// promising a drag that does nothing is the class of note this app has
    /// twice had to go back and correct.
    static let editHint = "Tap × to remove a key."

    /// Says the list ended, and how much of it there was.
    ///
    /// The pad scrolls now, and a run of keys that simply stops looks the same
    /// as one still loading more. Counting them is the cheap part; saying
    /// *that is all of it* is the point.
    ///
    /// Nil for an empty pad, which has its own note and does not need telling
    /// that nothing is all of it.
    static func endOfPad(_ pad: Pad) -> String? {
        let count = pad.treatment.count + pad.sources.count
        guard count > 0 else { return nil }
        return "That's the whole pad · \(count) \(count == 1 ? "key" : "keys")"
    }

    /// What an empty pad says.
    ///
    /// It used to end "and adding them by hand isn't built yet", which stopped
    /// being true the moment both add tiles existed — and it was saying so on
    /// the one screen where somebody needed to hear the opposite. A note about
    /// what is missing is worth less than nothing once it is quietly wrong.
    static let emptyNote = """
        There's nothing on your pad yet. Onboarding usually sets these up from \
        what you told us — add what you're quitting, and what you're treating \
        with, below.
        """

    /// The note's own styling, kept apart so the copy can be read without it.
    private struct EmptyNoteStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(AppFont.text(AppSize.caption))
                .lineSpacing(AppLeading.snug - AppSize.caption)
                .foregroundStyle(AppColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Never the same as empty. Drawing "nothing here yet" over a read that
    /// failed would invite somebody to rebuild a pad that is already on the
    /// server.
    private func unavailable(_ message: String) -> some View {
        Text(message)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.cautionInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.m)
            .background(AppColor.cautionSurface, in: RoundedRectangle(cornerRadius: AppRadius.small))
    }
}

#Preview {
    @Previewable @State var isSearching = false
    let keys: [StoredPadKey] = [
        StoredPadKey(id: 1, form: .patch, label: "Patch", mg: 21, position: 0, ndc: nil),
        StoredPadKey(id: 2, form: .lozenge, label: "Lozenge", mg: 4, position: 1, ndc: nil),
        StoredPadKey(id: 3, form: .pouch, label: "Pouches", mg: 3, position: 0, ndc: nil),
        StoredPadKey(id: 4, form: .vape, label: "Vape", mg: 2, position: 1, ndc: nil),
    ]
    let record = TodayRecord(store: nil)
    record.selection.tap(keys[2])
    return PadView(
        status: .ready(Pad(keys: keys)),
        record: record,
        ceilingMg: 12,
        search: TreatmentSearchRecord(search: nil),
        isSearching: $isSearching,
        draft: .constant(nil),
        draftFor: { NewKeyDraft(product: $0, store: nil) },
        sourceDraft: .constant(nil),
        newSourceDraft: { NewSourceDraft(store: nil) },
        onKeyAdded: { _ in },
        edit: PadEditRecord(store: nil),
        onKeyRemoved: { _ in }
    )
}
