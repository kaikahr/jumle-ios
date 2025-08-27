//
//  AudioPlayerService.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-07.
//

// File: Services/AudioPlayerService.swift

import AVFoundation
import Combine

final class AudioPlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentRate: Float = 1.0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    init() {
        configureSession()
    }

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("Audio session error:", error)
        }
    }

    func load(urlString: String) {
        guard let url = URL(string: urlString) else {
            print("Bad URL:", urlString)
            return
        }
        // Keep AVPlayer alive on the instance
        let item = AVPlayerItem(url: url)
        // Better quality time-stretching when changing rates
        item.audioTimePitchAlgorithm = .timeDomain

        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = true

        // Observe to help debug
        item.publisher(for: \.status, options: [.initial, .new])
            .sink { status in
                switch status {
                case .readyToPlay: print("Item ready")
                case .failed:      print("Item failed:", item.error ?? "unknown")
                case .unknown:     print("Item unknown")
                @unknown default:  break
                }
            }
            .store(in: &cancellables)
    }

    func play(rate: Float = 1.0) {
        guard let player = player else {
            print("Call load(urlString:) before play")
            return
        }
        currentRate = rate
        if rate == 1.0 {
            player.play() // 1x
        } else {
            player.play()
            player.rate = rate // e.g., 0.5x
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
                player.rate = rate
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
}
