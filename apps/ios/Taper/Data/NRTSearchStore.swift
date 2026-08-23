import Foundation
import Supabase

/// One licensed product as the Edge Function returns it: a single NDC at a
/// single strength. `grouped(_:)` says why that is not what a row is.
struct NRTProduct: Decodable, Equatable, Sendable {
    /// The National Drug Code. Carried through to the key that gets made from
    /// it, so a key built from the catalogue can be traced back to the label it
    /// came from.
    let id: String
    let brand: String
    let labeler: String
    let form: PadForm
    let mg: Double
}

/// A brand and form with every strength it comes in — one row of the search
/// screen. Strengths run low to high, which is the order a dose is read in.
struct NRTResult: Equatable, Sendable, Identifiable {
    let brand: String
    let labeler: String
    let form: PadForm
    /// Each strength, and the NDC that supplies it. A key needs the exact
    /// product, not just the number.
    let strengths: [(mg: Double, ndc: String)]

    var id: String { "\(brand)|\(form.rawValue)" }

    static func == (lhs: NRTResult, rhs: NRTResult) -> Bool {
        lhs.brand == rhs.brand && lhs.labeler == rhs.labeler && lhs.form == rhs.form
            && lhs.strengths.map(\.mg) == rhs.strengths.map(\.mg)
            && lhs.strengths.map(\.ndc) == rhs.strengths.map(\.ndc)
    }

    /// "Gum · nicotine polacrilex" — the form, then who makes it.
    var detailText: String {
        labeler.isEmpty ? form.label : "\(form.label) · \(labeler)"
    }
}

/// Searching the licensed NRT catalogue, where the restriction to licensed
/// nicotine replacement therapy is enforced by the `nrt-search` route rather
/// than here. It exposes no product-type or category parameter, so no client —
/// this one included — can widen discovery to pouches, vapes or anything else
/// the app is not licensed to recommend.
protocol NRTSearching: Sendable {
    /// Products matching a brand name, grouped by brand and form.
    ///
    /// An empty array means *nothing matched*, never *the lookup failed*. The
    /// screen says different things about those two and one of them is a retry.
    func search(_ query: String) async throws -> [NRTResult]
}

/// Searches the licensed catalogue through the `nrt-search` Edge Function.
struct SupabaseNRTSearch: NRTSearching {
    let client: SupabaseClient
    let session: SessionCoordinator
    /// How many rows to ask for. Above the number a person will read and below
    /// the function's own ceiling of 25.
    var limit = 20

    private struct Body: Encodable {
        let query: String
        let limit: Int
    }

    private struct Payload: Decodable {
        let products: [NRTProduct]
    }

    func search(_ query: String) async throws -> [NRTResult] {
        let trimmed = Self.asked(from: query)
        guard !trimmed.isEmpty else { return [] }

        let payload: Payload = try await session.authenticated { _ in
            try await client.functions.invoke(
                "nrt-search",
                options: FunctionInvokeOptions(body: Body(query: trimmed, limit: limit))
            )
        }
        return Self.grouped(payload.products)
    }

    /// What is actually sent, or empty when there is nothing worth sending.
    ///
    /// Trimmed and checked before the round trip: the function answers 400 to
    /// an empty query, and a request whose only possible outcome is an error is
    /// one nobody should have to wait for. A field holding two spaces is empty
    /// as far as a catalogue is concerned.
    ///
    /// Separate from `search` so it can be checked at all — that method needs a
    /// live client, so this is the only part of the request path a test can
    /// reach.
    static func asked(from query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Collapses one row per NDC into one row per brand and form.
    ///
    /// openFDA lists every strength as its own product, so a search for a gum
    /// brand returns the 2 mg and the 4 mg as separate records. Offering both
    /// as results asks somebody to choose a strength before they have chosen a
    /// product — the board draws one row with the strengths as chips, and this
    /// is that shape.
    ///
    /// Order is the order the function returned, which is openFDA's relevance.
    /// Re-sorting here would put the app's opinion in front of the label's.
    static func grouped(_ products: [NRTProduct]) -> [NRTResult] {
        var order: [String] = []
        var byKey: [String: [NRTProduct]] = [:]

        for product in products {
            let key = "\(product.brand)|\(product.form.rawValue)"
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(product)
        }

        return order.compactMap { key in
            guard let group = byKey[key], let first = group.first else { return nil }
            // Distinct strengths, low to high. A brand listing the same
            // milligrams under two NDCs is one chip, not two identical ones.
            var seen: Set<Double> = []
            let strengths = group
                .sorted { $0.mg < $1.mg }
                .filter { seen.insert($0.mg).inserted }
                .map { (mg: $0.mg, ndc: $0.id) }

            return NRTResult(
                brand: first.brand, labeler: first.labeler, form: first.form, strengths: strengths
            )
        }
    }
}
