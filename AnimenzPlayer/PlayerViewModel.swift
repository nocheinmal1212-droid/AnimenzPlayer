import Foundation
import AVFoundation
import Combine

final class PlayerViewModel: NSObject, ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying: Bool = false
    @Published var isShuffled: Bool = false {
        didSet { rebuildQueue(preservingCurrent: true) }
    }
    @Published private(set) var progress: Double = 0
    @Published private(set) var duration: Double = 0

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var playQueue: [Track] = []
    private var currentIndex: Int = 0

    override init() {
        super.init()
        configureAudioSession()
        loadTracks()
    }

    // MARK: - Setup

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        #endif
    }

    private func loadTracks() {
        let fm = FileManager.default
        var audioURLs: [URL] = []

        // Preferred: "Music" folder reference inside the bundle
        if let musicURL = Bundle.main.url(forResource: "Music", withExtension: nil),
           let urls = try? fm.contentsOfDirectory(
            at: musicURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
           ) {
            audioURLs = urls
        } else if let resourceURL = Bundle.main.resourceURL,
                  let urls = try? fm.contentsOfDirectory(
                    at: resourceURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                  ) {
            // Fallback: flat resource bundle
            audioURLs = urls
        }

        let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "flac", "aiff", "caf"]
        let filtered = audioURLs.filter {
            audioExtensions.contains($0.pathExtension.lowercased())
        }

        tracks = filtered.map(Track.init).sorted { $0.index < $1.index }
        playQueue = tracks
    }

    // MARK: - Playback

    func play(_ track: Track) {
        if !playQueue.contains(track) {
            rebuildQueue(preservingCurrent: false)
        }
        if let idx = playQueue.firstIndex(of: track) {
            currentIndex = idx
        }
        loadAndPlay(track)
    }

    private func loadAndPlay(_ track: Track) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: track.url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            currentTrack = track
            isPlaying = true
            duration = audioPlayer?.duration ?? 0
            progress = 0
            startTimer()
        } catch {
            print("Failed to play \(track.title): \(error)")
        }
    }

    func togglePlayPause() {
        guard let audioPlayer else {
            if let first = playQueue.first { play(first) }
            return
        }
        if audioPlayer.isPlaying {
            audioPlayer.pause()
            isPlaying = false
        } else {
            audioPlayer.play()
            isPlaying = true
        }
    }

    func next() {
        guard !playQueue.isEmpty else { return }
        currentIndex = (currentIndex + 1) % playQueue.count
        loadAndPlay(playQueue[currentIndex])
    }

    func previous() {
        guard !playQueue.isEmpty else { return }
        // If more than 3s into the track, restart it instead of going back
        if let audioPlayer, audioPlayer.currentTime > 3 {
            audioPlayer.currentTime = 0
            progress = 0
            return
        }
        currentIndex = (currentIndex - 1 + playQueue.count) % playQueue.count
        loadAndPlay(playQueue[currentIndex])
    }

    func seek(to time: Double) {
        audioPlayer?.currentTime = time
        progress = time
    }

    // MARK: - Queue management

    private func rebuildQueue(preservingCurrent: Bool) {
        let current = currentTrack
        playQueue = isShuffled ? tracks.shuffled() : tracks
        if preservingCurrent, let current, let idx = playQueue.firstIndex(of: current) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let audioPlayer = self.audioPlayer else { return }
            self.progress = audioPlayer.currentTime
        }
    }
}

extension PlayerViewModel: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Continuous playback — auto-advance
        next()
    }
}
