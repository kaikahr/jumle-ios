//  SentenceCardView.swift
//  jumle
//
// File: Components/SentenceCardView.swift - Optimized for Xcode performance
import SwiftUI
import AVFoundation

struct SentenceCardView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var audio: AudioPlayerService
    @EnvironmentObject private var session: SessionViewModel
    @EnvironmentObject private var learned: LearnedStore
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var scheme

    let sentence: Sentence
    var displayLanguage: AppLanguage? = nil

    @State private var showTranslation = false
    @State private var showExplainSheet = false
    @State private var showContextSheet = false
    @State private var explainText: String?
    @State private var contextText: String?
    @State private var isLoadingExplain = false
    @State private var isLoadingContext = false

    // Computed properties broken out for clarity
    private var hasAudio: Bool {
        sentence.text(for: mainLang) != nil
    }
    
    private var mainLang: AppLanguage {
        displayLanguage ?? app.learningLanguage
    }
    
    private var mainText: String? {
        sentence.text(for: mainLang)
    }
    
    private var translatedText: String? {
        sentence.text(for: app.knownLanguage)
    }
    
    private var isLearned: Bool {
        learned.isLearned(sentenceId: sentence.id, language: mainLang)
    }

    var body: some View {
        VStack(spacing: 12) {
            TopicLabel(topic: sentence.topics.first)
            MainTextView(text: mainText, language: mainLang)
            TranslationView(text: translatedText, isVisible: showTranslation)
            AudioControlsView(
                hasAudio: hasAudio,
                isPremium: subscriptionManager.isPremium,
                showTranslation: $showTranslation,
                onPlayAudio: playAudio
            )
            AudioErrorView(loadingState: audio.loadingState)
            AIFeaturesView(
                isPremium: subscriptionManager.isPremium,
                onExplain: handleExplain,
                onContext: handleContext
            )
        }
        .cardStyle(scheme: scheme)
        .overlay(alignment: .topTrailing) {
            LearnedButton(isLearned: isLearned, onToggle: handleToggleLearned)
        }
        .aiSheets(
            showExplain: $showExplainSheet,
            showContext: $showContextSheet,
            isLoadingExplain: isLoadingExplain,
            isLoadingContext: isLoadingContext,
            explainText: explainText,
            contextText: contextText,
            aiError: app.aiError
        )
        .sheet(isPresented: $subscriptionManager.showPaywall) {
            SubscriptionPaywallView()
                .environmentObject(subscriptionManager)
        }
        .onDisappear { audio.stop() }
        .animation(.easeInOut(duration: 0.2), value: showTranslation)
        .animation(.easeInOut(duration: 0.2), value: learned.learnedIDs)
    }
}

// MARK: - Action Handlers
private extension SentenceCardView {
    func playAudio(rate: Float) {
        if rate != 1.0 && !subscriptionManager.isPremium {
            subscriptionManager.showPaywallForFeature("audio_speeds")
            return
        }
        
        guard let audioURL = app.audioURL(for: sentence, language: mainLang) else {
            print("❌ Could not generate audio URL for sentence \(sentence.id) in \(mainLang.displayName)")
            return
        }
        
        print("🎵 Playing audio at \(rate)x speed: \(audioURL.absoluteString)")
        audio.loadAndPlay(urlString: audioURL.absoluteString, rate: rate)
    }
    
    func handleExplain() {
        guard subscriptionManager.canUseAIFeatures() else {
            subscriptionManager.showPaywallForFeature("ai_features")
            return
        }
        guard session.ensureSignedIn() else { return }
        
        showExplainSheet = true
        isLoadingExplain = true
        explainText = nil
        
        Task {
            let txt = await app.explain(sentence: sentence)
            await MainActor.run {
                explainText = txt
                isLoadingExplain = false
            }
        }
    }
    
    func handleContext() {
        guard subscriptionManager.canUseAIFeatures() else {
            subscriptionManager.showPaywallForFeature("ai_features")
            return
        }
        guard session.ensureSignedIn() else { return }
        
        showContextSheet = true
        isLoadingContext = true
        contextText = nil
        
        Task {
            let txt = await app.contextualize(sentence: sentence)
            await MainActor.run {
                contextText = txt
                isLoadingContext = false
            }
        }
    }
    
    func handleToggleLearned() {
        guard session.ensureSignedIn() else { return }
        
        Task {
            let turnedOn = await learned.toggleLearned(sentence: sentence, language: mainLang)
            await MainActor.run {
                if turnedOn && !app.saved.contains(sentence.id) {
                    app.toggleSave(sentence, subscriptionManager: subscriptionManager)
                } else if !turnedOn && app.saved.contains(sentence.id) {
                    app.toggleSave(sentence, subscriptionManager: subscriptionManager)
                }
            }
        }
    }
}

// MARK: - Subviews
private struct TopicLabel: View {
    let topic: String?
    
    var body: some View {
        if let topic = topic, !topic.isEmpty {
            Label(topic, systemImage: "tag.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.25), lineWidth: 1))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        }
    }
}

private struct MainTextView: View {
    let text: String?
    let language: AppLanguage
    
    var body: some View {
        if let text = text {
            Text(text)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        } else {
            Text("Missing \(language.displayName) text.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

private struct TranslationView: View {
    let text: String?
    let isVisible: Bool
    
    var body: some View {
        if isVisible, let text = text {
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}

private struct AudioControlsView: View {
    let hasAudio: Bool
    let isPremium: Bool
    @Binding var showTranslation: Bool
    let onPlayAudio: (Float) -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // 0.5x speed button
            AudioSpeedButton(
                rate: 0.5,
                hasAudio: hasAudio,
                isPremium: isPremium,
                onPlay: onPlayAudio
            )
            
            // 1x speed button
            AudioSpeedButton(
                rate: 1.0,
                hasAudio: hasAudio,
                isPremium: true, // Always available
                onPlay: onPlayAudio
            )
            
            // Translate button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTranslation.toggle()
                }
            } label: {
                Label(showTranslation ? "Hide" : "Translate",
                      systemImage: showTranslation ? "eye.slash" : "globe")
                    .font(.subheadline)
            }
            .buttonStyle(StablePillButtonStyle(
                fill: Color.accentColor.opacity(0.14),
                height: 42
            ))
        }
        .padding(.horizontal, 8)
    }
}

private struct AudioSpeedButton: View {
    let rate: Float
    let hasAudio: Bool
    let isPremium: Bool
    let onPlay: (Float) -> Void
    
    private var iconName: String {
        if rate == 0.5 {
            return isPremium ? "speaker.wave.2.fill" : "lock.fill"
        } else {
            return "play.fill"
        }
    }
    
    private var fillColor: Color {
        if !isPremium {
            return Color(.tertiarySystemBackground)
        } else {
            return hasAudio ? Color(.secondarySystemBackground) : Color(.tertiarySystemBackground)
        }
    }
    
    var body: some View {
        Button {
            onPlay(rate)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                Text("\(rate, specifier: "%.1f")×")
            }
            .font(.subheadline)
            .accessibilityLabel("Play at \(rate == 0.5 ? "half" : "normal") speed")
        }
        .disabled(!hasAudio)
        .buttonStyle(StablePillButtonStyle(fill: fillColor, height: 42))
    }
}

private struct AudioErrorView: View {
    let loadingState: AudioPlayerService.LoadingState?
    
    var body: some View {
        if case .failed(let error) = loadingState {
            Text("Audio error: \(error)")
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

private struct AIFeaturesView: View {
    let isPremium: Bool
    let onExplain: () -> Void
    let onContext: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            AIFeatureButton(
                title: "Explain",
                icon: isPremium ? "questionmark.circle" : "lock.fill",
                isPremium: isPremium,
                action: onExplain
            )
            
            AIFeatureButton(
                title: "Context",
                icon: isPremium ? "text.justify.left" : "lock.fill",
                isPremium: isPremium,
                action: onContext
            )
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

private struct AIFeatureButton: View {
    let title: String
    let icon: String
    let isPremium: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline)
        }
        .buttonStyle(StablePillButtonStyle(
            fill: isPremium ? Color(.secondarySystemBackground) : Color(.tertiarySystemBackground),
            height: 44
        ))
    }
}

private struct LearnedButton: View {
    let isLearned: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isLearned ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isLearned ? .green : .secondary)
                .padding(10)
                .background(Color(.secondarySystemBackground).opacity(0.92), in: Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                .shadow(radius: 1, y: 1)
                .accessibilityLabel(isLearned ? "Learned" : "Mark learned")
                .id(isLearned)
        }
        .padding(10)
        .buttonStyle(.plain)
    }
}

// MARK: - View Extensions
private extension View {
    func cardStyle(scheme: ColorScheme) -> some View {
        let background = LinearGradient(
            colors: [
                scheme == .dark ? Color.black.opacity(0.15) : Color.white,
                Color.accentColor.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        return self
            .padding(.top, 20)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .frame(maxWidth: 420)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(scheme == .dark ? 0.25 : 0.06),
                radius: 8, x: 0, y: 4
            )
            .contentShape(Rectangle())
    }
    
    func aiSheets(
        showExplain: Binding<Bool>,
        showContext: Binding<Bool>,
        isLoadingExplain: Bool,
        isLoadingContext: Bool,
        explainText: String?,
        contextText: String?,
        aiError: String?
    ) -> some View {
        self
            .sheet(isPresented: showExplain) {
                AISheetView(
                    title: "Explanation",
                    isLoading: isLoadingExplain,
                    text: explainText,
                    error: aiError,
                    loadingMessage: "Explaining…",
                    onDismiss: { showExplain.wrappedValue = false }
                )
            }
            .sheet(isPresented: showContext) {
                AISheetView(
                    title: "Context",
                    isLoading: isLoadingContext,
                    text: contextText,
                    error: aiError,
                    loadingMessage: "Building context…",
                    onDismiss: { showContext.wrappedValue = false }
                )
            }
    }
}

private struct AISheetView: View {
    let title: String
    let isLoading: Bool
    let text: String?
    let error: String?
    let loadingMessage: String
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(loadingMessage)
                } else if let text = text {
                    ScrollView {
                        Text(text).padding()
                    }
                } else {
                    Text(error ?? "No \(title.lowercased()).")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
