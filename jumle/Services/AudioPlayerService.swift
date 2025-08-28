// File: Services/AudioPlayerService.swift - Fixed version

import AVFoundation
import Combine

final class AudioPlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentRate: Float = 1.0
    @Published var loadingState: LoadingState = .idle
    
    enum LoadingState {
        case idle, loading, loaded, failed(String)
    }

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    // Keep track of current URL to avoid reloading same audio
    private var currentURL: String?
    
    // Simple cache to avoid recreating URLs
    private let urlCache = NSCache<NSString, NSURL>()

    init() {
        configureAudioSession()
        // Configure cache limits for memory efficiency
        urlCache.countLimit = 50 // Cache up to 50 URLs
    }
    
    deinit {
        cleanupPlayer()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
            print("✅ Audio session configured successfully")
        } catch {
            print("❌ Audio session error: \(error.localizedDescription)")
        }
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        playerItem = nil
        isPlaying = false
        cancellables.removeAll()
    }

    func load(urlString: String) {
        // Don't reload if it's the same URL and player is ready
        if currentURL == urlString,
           let player = player,
           player.currentItem?.status == .readyToPlay {
            return
        }
        
        // Cache the URL object to avoid repeated parsing
        let url: URL
        if let cachedURL = urlCache.object(forKey: urlString as NSString) as URL? {
            url = cachedURL
        } else {
            guard let newURL = URL(string: urlString) else {
                loadingState = .failed("Invalid audio URL")
                return
            }
            url = newURL
            urlCache.setObject(url as NSURL, forKey: urlString as NSString)
        }
        
        loadingState = .loading
        
        // Clean up previous player
        cleanupPlayer()
        
        // Create new player item
        playerItem = AVPlayerItem(url: url)
        
        // Configure for better quality time-stretching
        playerItem?.audioTimePitchAlgorithm = .timeDomain
        
        // Create player
        player = AVPlayer(playerItem: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = false
        
        // Set current URL
        currentURL = urlString
        
        // Observe player item status
        playerItem?.publisher(for: \.status, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay:
                    self.loadingState = .loaded
                case .failed:
                    let error = self.playerItem?.error?.localizedDescription ?? "Unknown error"
                    self.loadingState = .failed(error)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Observe playback completion
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isPlaying = false
            }
            .store(in: &cancellables)
    }

    func play(rate: Float = 1.0) {
        guard let player = player else {
            return
        }
        
        guard player.currentItem?.status == .readyToPlay else {
            return
        }
        
        currentRate = rate
        
        // Seek to beginning if at end
        if player.currentTime() >= player.currentItem?.duration ?? CMTime.zero {
            player.seek(to: .zero)
        }
        
        // Start playback
        player.play()
        
        // Set custom rate if needed (after calling play())
        if rate != 1.0 {
            // Small delay to ensure playback has started
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                player.rate = rate
            }
        }
        
        isPlaying = true
    }

    func setRate(_ rate: Float) {
        guard let player = player else { return }
        currentRate = rate
        if isPlaying {
            if rate == 1.0 {
                player.play()
            } else {
                player.play()
                // Small delay before setting custom rate
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    player.rate = rate
                }
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
    }
    
    // Convenience method to load and play in one call
    func loadAndPlay(urlString: String, rate: Float = 1.0) {
        load(urlString: urlString)
        
        // If already loaded, play immediately
        if case .loaded = loadingState {
            play(rate: rate)
        } else {
            // Wait for loading to complete, then play
            $loadingState
                .filter { state in
                    if case .loaded = state { return true }
                    if case .failed = state { return true }
                    return false
                }
                .first()
                .sink { [weak self] state in
                    if case .loaded = state {
                        self?.play(rate: rate)
                    }
                }
                .store(in: &cancellables)
        }
    }
}
