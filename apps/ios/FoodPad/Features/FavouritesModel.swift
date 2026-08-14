import Foundation

@MainActor
final class FavouritesModel: ObservableObject {
    @Published private(set) var ids: Set<Int> = []
    private let read: @Sendable () async throws -> Set<Int>
    private let persist: @Sendable (Bool, Int) async throws -> Void
    private var loaded = false
    private var loading: Task<Set<Int>, Error>?
    private var pressedDuringLoad: [Int: Bool]?
    private var chains: [Int: Task<Void, Never>] = [:]
    private var generations: [Int: Int] = [:]

    init(
        read: @escaping @Sendable () async throws -> Set<Int>,
        persist: @escaping @Sendable (Bool, Int) async throws -> Void
    ) {
        self.read = read
        self.persist = persist
    }

    func load() async {
        if loaded { return }
        if let loading { _ = try? await loading.value; return }
        pressedDuringLoad = [:]
        let task = Task { try await read() }
        loading = task
        do {
            var fetched = try await task.value
            for (fdcID, on) in pressedDuringLoad ?? [:] {
                if on { fetched.insert(fdcID) } else { fetched.remove(fdcID) }
            }
            ids = fetched
            loaded = true
        } catch {}
        pressedDuringLoad = nil
        loading = nil
    }

    func toggle(_ fdcID: Int) async {
        let previous = chains[fdcID]
        let generation = (generations[fdcID] ?? 0) + 1
        generations[fdcID] = generation
        let task = Task { [weak self] in
            await previous?.value
            await self?.write(fdcID)
        }
        chains[fdcID] = task
        await task.value
        if generations[fdcID] == generation { chains[fdcID] = nil }
    }

    private func write(_ fdcID: Int) async {
        let on = !ids.contains(fdcID)
        update(fdcID, on: on)
        do { try await persist(on, fdcID) }
        catch { update(fdcID, on: !on) }
    }

    private func update(_ fdcID: Int, on: Bool) {
        if on { ids.insert(fdcID) } else { ids.remove(fdcID) }
        pressedDuringLoad?[fdcID] = on
    }
}
