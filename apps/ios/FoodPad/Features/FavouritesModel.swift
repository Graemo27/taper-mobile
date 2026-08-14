import Foundation

@MainActor
final class FavouritesModel: ObservableObject {
    @Published private(set) var ids: Set<Int> = []
    private let read: @Sendable () async throws -> Set<Int>
    private let persist: @Sendable (Bool, Int) async throws -> Void
    private var loaded = false
    private var loading: Task<Set<Int>, Error>?
    private var requested: [Int: Bool] = [:]
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
        let task = Task { try await read() }
        loading = task
        do {
            var fetched = try await task.value
            for (fdcID, on) in requested {
                if on { fetched.insert(fdcID) } else { fetched.remove(fdcID) }
            }
            ids = fetched
            loaded = true
        } catch {}
        loading = nil
    }

    @discardableResult
    func toggle(_ fdcID: Int) -> Task<Void, Never> {
        let generation = (generations[fdcID] ?? 0) + 1
        generations[fdcID] = generation
        let on = !ids.contains(fdcID)
        update(fdcID, on: on)
        let previous = chains[fdcID]
        let task = Task { [weak self] in
            await previous?.value
            await self?.write(fdcID, on: on, generation: generation)
        }
        chains[fdcID] = task
        return task
    }

    private func write(_ fdcID: Int, on: Bool, generation: Int) async {
        do { try await persist(on, fdcID) }
        catch where generations[fdcID] == generation { update(fdcID, on: !on) }
        catch {}
        if generations[fdcID] == generation { chains[fdcID] = nil }
    }

    private func update(_ fdcID: Int, on: Bool) {
        if on { ids.insert(fdcID) } else { ids.remove(fdcID) }
        requested[fdcID] = on
    }
}
