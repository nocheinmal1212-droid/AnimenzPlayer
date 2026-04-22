import Foundation
import Combine

/// Disk-backed user state. Writes are debounced so rapid mutations (e.g. scrub
/// dragging) don't hit the filesystem on every tick.
///
/// Designed to grow: add fields to `State` and they'll be serialized without
/// any changes here. JSON is used over SwiftData/Core Data because the state
/// is tiny and we want to keep the surface area small for Wave 1.
///
/// Pass `fileURL: nil` to get an in-memory-only store (used by tests and
/// previews).
@MainActor
final class PersistenceStore: ObservableObject {
    struct State: Codable, Equatable {
        // MARK: Wave 1
        var lastTrackURL: URL?
        var lastPosition: Double = 0
        var isShuffled: Bool = false

        // MARK: Wave 2
        /// Repeat mode. Defaulted to `.off` so old state files decode.
        var repeatMode: RepeatMode = .off
        /// URLs the user has hearted. Stored as Set for O(1) membership;
        /// Codable handles Set<URL> natively.
        var favorites: Set<URL> = []
        /// Most-recently-played track URLs, newest first. Capped — see
        /// `PlayerViewModel.recordPlay(_:)`.
        var recentlyPlayed: [URL] = []
    }

    @Published private(set) var state: State

    private let fileURL: URL?
    private let debouncer: Debouncer

    init(fileURL: URL? = PersistenceStore.defaultFileURL(), debounce: TimeInterval = 0.5) {
        self.fileURL = fileURL
        self.debouncer = Debouncer(interval: debounce)
        self.state = fileURL.flatMap(Self.loadState(from:)) ?? State()
    }

    /// Mutates state and schedules a debounced write.
    func update(_ transform: (inout State) -> Void) {
        transform(&state)
        scheduleWrite()
    }

    /// Flush pending writes immediately. Call from e.g. `scenePhase == .background`.
    func flush() {
        debouncer.cancel()
        writeNow()
    }

    // MARK: - Defaults

    /// `nonisolated` so this can be called from default-argument expressions,
    /// which Swift evaluates in a synchronous nonisolated context even when
    /// the initializer itself is `@MainActor`. The body only touches
    /// `FileManager` and `Bundle`, neither of which is actor-isolated.
    nonisolated static func defaultFileURL() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let bundleID = Bundle.main.bundleIdentifier ?? "AnimenzPlayer"
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("player-state.json")
    }

    // MARK: - Private

    private func scheduleWrite() {
        debouncer.schedule { [weak self] in
            self?.writeNow()
        }
    }

    private func writeNow() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence is best-effort — losing state on write failure is
            // recoverable (worst case the user's last position doesn't survive).
            print("PersistenceStore: write failed — \(error)")
        }
    }

    private static func loadState(from url: URL) -> State? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }
}

/// Tiny debouncer. Not thread-safe by design — meant to be called from a
/// single actor (here, MainActor).
final class Debouncer {
    private let interval: TimeInterval
    private var workItem: DispatchWorkItem?

    init(interval: TimeInterval) { self.interval = interval }

    func schedule(_ action: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
