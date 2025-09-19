// File: Services/AudioPlayerService.swift - Crash-safe, main-thread aligned

import AVFoundation
import Combine

final class AudioPlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentRate: Float = 1.0
    @Published var loadingState: LoadingState = .idle
    
    enum LoadingState {
        case idle, loading, loaded, failed(String)
    }

    // MARK: - Private state

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    
    // Strong references to KVO observations (must invalidate before swap)
    private var statusObs: NSKeyValueObservation?
    private var timeControlObs: NSKeyValueObservation?
    
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    // Avoid redundant reloads
    private var currentURL: String?
    
    // Small URL cache
    private let urlCache = NSCache<NSString, NSURL>()
    
    // Serialize all AV work on main (Apple recommends using main for AVFoundation objects)
    private let avQueue = DispatchQueue.main

    // If a play() was requested before item became ready, remember desired rate
    private var pendingPlayRate: Float?

    init() {
        configureAudioSession()
        urlCache.countLimit = 50
    }
    
    deinit {
        cleanupPlayer(teardownSession: true)
    }

    // MARK: - Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP, .duckOthers])
            try session.setActive(true)
            print("✅ Audio session configured")
        } catch {
            print("❌ Audio session error:", error.localizedDescription)
        }
    }

    // MARK: - Cleanup

    private func cleanupPlayer(teardownSession: Bool = false) {
        avQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Invalidate KVO safely before nulling things out
            self.statusObs?.invalidate(); self.statusObs = nil
            self.timeControlObs?.invalidate(); self.timeControlObs = nil
            
            if let t = self.timeObserver, let p = self.player {
                p.removeTimeObserver(t)
            }
            self.timeObserver = nil
            
            self.player?.pause()
            self.playerItem = nil
            self.isPlaying = false
            self.loadingState = .idle
            self.pendingPlayRate = nil
            self.cancellables.removeAll()
            
            if teardownSession {
                // Optional: leave session active for smoother UX, but allow full teardown if needed
                try? AVAudioSession.sharedInstance().setActive(false, options: [])
            }
        }
    }

    // MARK: - Public API
    
    /// Prepares (or swaps) the current item. Safe to call repeatedly.
    func load(urlString: String) {
        avQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Fast-path: already loaded and ready
            if self.currentURL == urlString,
               let item = self.player?.currentItem,
               item.status == .readyToPlay {
                self.loadingState = .loaded
                return
            }
            
            // Resolve URL via small cache
            let url: URL
            if let cached = self.urlCache.object(forKey: urlString as NSString) as URL? {
                url = cached
            } else {
                guard let u = URL(string: urlString), (u.scheme?.lowercased() == "https") else {
                    self.loadingState = .failed("Invalid or unsupported URL")
                    return
                }
                url = u
                self.urlCache.setObject(url as NSURL, forKey: urlString as NSString)
            }
            
            self.loadingState = .loading
            
            // Ensure a player exists; reuse it
            let player = self.player ?? AVPlayer()
            self.player = player
            player.automaticallyWaitsToMinimizeStalling = true
            
            // Invalidate observers before swapping
            self.statusObs?.invalidate(); self.statusObs = nil
            self.timeControlObs?.invalidate(); self.timeControlObs = nil
            
            // Pause before replace to avoid race
            player.pause()
            
            // Create & configure item
            let item = AVPlayerItem(url: url)
            item.audioTimePitchAlgorithm = .timeDomain
            
            self.playerItem = item
            self.currentURL = urlString
            
            // Replace current item (safer than creating a new AVPlayer each time)
            player.replaceCurrentItem(with: item)
            
            // Observe item readiness
            self.statusObs = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard let self = self else { return }
                switch item.status {
                case .readyToPlay:
                    self.loadingState = .loaded
                    // If a play was requested while loading, start now
                    if let desiredRate = self.pendingPlayRate {
                        self.internalPlay(rate: desiredRate)
                        self.pendingPlayRate = nil
                    }
                case .failed:
                    let msg = item.error?.localizedDescription ?? "Unknown error"
                    self.loadingState = .failed(msg)
                    self.isPlaying = false
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
            
            // Observe overall player timeControlStatus for UI state
            self.timeControlObs = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.isPlaying = (p.timeControlStatus == .playing)
                }
            }
            
            // Playback finished
            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.isPlaying = false
                }
                .store(in: &self.cancellables)
        }
    }

    /// Starts playback if ready; otherwise defers until the item becomes ready.
    func play(rate: Float = 1.0) {
        avQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentRate = rate
            guard let item = self.player?.currentItem else { return }
            
            if item.status == .readyToPlay {
                self.internalPlay(rate: rate)
            } else {
                // Defer play until .readyToPlay
                self.pendingPlayRate = rate
            }
        }
    }
    
    /// Change rate during playback.
    func setRate(_ rate: Float) {
        avQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentRate = rate
            guard self.isPlaying, let player = self.player else { return }
            // Use playImmediately for consistent rate take-up
            player.playImmediately(atRate: max(0.25, min(rate, 2.0)))
        }
    }

    func pause() {
        avQueue.async { [weak self] in
            self?.player?.pause()
            self?.isPlaying = false
            self?.pendingPlayRate = nil
        }
    }

    func stop() {
        avQueue.async { [weak self] in
            guard let self = self else { return }
            self.player?.pause()
            self.player?.seek(to: .zero)
            self.isPlaying = false
            self.pendingPlayRate = nil
        }
    }
    
    /// Convenience: load and then play when ready.
    func loadAndPlay(urlString: String, rate: Float = 1.0) {
        // Set a one-shot waiter for loaded/failed
        avQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel any prior waiters
            self.cancellables.removeAll()
            
            // Start load (may synchronously resolve to .loaded if already ready)
            self.load(urlString: urlString)
            
            // If already loaded, just play
            if case .loaded = self.loadingState {
                self.play(rate: rate)
                return
            }
            
            // Otherwise wait once for loaded/failed then act
            self.$loadingState
                .filter { state in
                    if case .loaded = state { return true }
                    if case .failed = state { return true }
                    return false
                }
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self else { return }
                    if case .loaded = state {
                        self.play(rate: rate)
                    }
                }
                .store(in: &self.cancellables)
        }
    }

    // MARK: - Helpers
    
    private func internalPlay(rate: Float) {
        guard let player = player, let item = player.currentItem, item.status == .readyToPlay else { return }
        
        // If at/near end, seek to start
        let duration = item.duration
        if duration.isNumeric, player.currentTime() >= duration {
            player.seek(to: .zero)
        }
        
        // Start immediately at requested rate to avoid race with setRate after play()
        player.playImmediately(atRate: max(0.25, min(rate, 2.0)))
        isPlaying = true
    }
}

private extension CMTime {
    var isNumeric: Bool { flags.contains(.valid) && !flags.contains(.indefinite) && isNumericValue }
    private var isNumericValue: Bool { timescale != 0 && isValid }
}
