import Foundation
@testable import AnimenzPlayer

/// Drop-in PlaybackEngine for unit tests. Inspects state and exposes hooks to
/// synthesize engine events without actually decoding audio.
final class MockPlaybackEngine: PlaybackEngine {
    // PlaybackEngine state
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying: Bool = false

    // Test-visible record of what the view model asked us to do.
    private(set) var loadedURLs: [URL] = []
    private(set) var playCallCount: Int = 0
    private(set) var pauseCallCount: Int = 0
    private(set) var seekTargets: [Double] = []
    private(set) var stopCallCount: Int = 0

    // Configurable failure modes.
    var loadError: Error?
    var simulatedDuration: Double = 180

    // Callbacks
    var onTimeChange: ((Double) -> Void)?
    var onDurationChange: ((Double) -> Void)?
    var onPlayingChange: ((Bool) -> Void)?
    var onFinish: (() -> Void)?
    var onError: ((PlayerError) -> Void)?

    // MARK: PlaybackEngine

    func load(url: URL) async throws {
        loadedURLs.append(url)
        if let loadError {
            throw loadError
        }
        duration = simulatedDuration
        currentTime = 0
        onDurationChange?(duration)
        onTimeChange?(0)
    }

    func play() {
        playCallCount += 1
        isPlaying = true
        onPlayingChange?(true)
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
        onPlayingChange?(false)
    }

    func seek(to time: Double) async {
        seekTargets.append(time)
        currentTime = time
        onTimeChange?(time)
    }

    func stop() {
        stopCallCount += 1
        isPlaying = false
        currentTime = 0
        duration = 0
        onPlayingChange?(false)
    }

    // MARK: Test hooks

    func simulateFinish() {
        onFinish?()
    }

    func simulateTimeTick(_ t: Double) {
        currentTime = t
        onTimeChange?(t)
    }

    func simulateError(_ error: PlayerError) {
        onError?(error)
    }
}

// MARK: - Track helpers

enum TestTrack {
    static func make(index: Int, title: String = "Song") -> Track {
        let filename = String(format: "%03d - %@.m4a", index, title)
        return Track(url: URL(fileURLWithPath: "/tmp/\(filename)"))
    }

    static func library(count: Int) -> [Track] {
        (1...count).map { make(index: $0, title: "Song \($0)") }
    }
}
