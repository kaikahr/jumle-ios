//
//  SentenceCardView.swift
//  jumle
//
// File: Components/SentenceCardView.swift
import SwiftUI
import AVFoundation

struct SentenceCardView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var audio: AudioPlayerService
    @EnvironmentObject private var session: SessionViewModel   // auth session
    @EnvironmentObject private var learned: LearnedStore       // ✅ Learned store
    @Environment(\.colorScheme) private var scheme

    let sentence: Sentence
    var displayLanguage: AppLanguage? = nil

    @State private var showTranslation = false

    // Explain/Context sheets (kept)
    @State private var showExplainSheet = false
    @State private var showContextSheet = false
    @State private var explainText: String?
    @State private var contextText: String?
    @State private var isLoadingExplain = false
    @State private var isLoadingContext = false

    private var hasAudio: Bool { app.audioURL(for: sentence) != nil }
    private var mainLang: AppLanguage { displayLanguage ?? app.learningLanguage }

    private func playAudio(rate: Float) {
        guard let url = app.audioURL(for: sentence) else { return }
        audio.load(urlString: url.absoluteString)
        audio.play(rate: rate)
    }

    var body: some View {
        let mainText: String? = sentence.text(for: mainLang)
        let translatedText: String? = sentence.text(for: app.knownLanguage)

        let tint = Color.accentColor
        let background = LinearGradient(
            colors: [
                scheme == .dark ? Color.black.opacity(0.15) : Color.white,
                tint.opacity(0.06)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        VStack(spacing: 12) {
            if let topic = sentence.topics.first, !topic.isEmpty {
                Label(topic, systemImage: "tag.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 1))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }

            if let main = mainText {
                Text(main)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("Missing \(mainLang.displayName) text.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if showTranslation, let t = translatedText {
                Text(t)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            // Audio + translate row
            HStack(spacing: 10) {
                Button { playAudio(rate: 0.5) } label: {
                    Label("0.5×", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline)
                        .accessibilityLabel("Play at half speed")
                }
                .disabled(!hasAudio)
                .buttonStyle(StablePillButtonStyle(height: 42))

                Button { playAudio(rate: 1.0) } label: {
                    Label("1×", systemImage: "play.fill")
                        .font(.subheadline)
                        .accessibilityLabel("Play at normal speed")
                }
                .disabled(!hasAudio)
                .buttonStyle(StablePillButtonStyle(height: 42))

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showTranslation.toggle() }
                } label: {
                    Label(showTranslation ? "Hide" : "Translate",
                          systemImage: showTranslation ? "eye.slash" : "globe")
                        .font(.subheadline)
                }
                .buttonStyle(StablePillButtonStyle(fill: tint.opacity(0.14), height: 42))
            }
            .padding(.horizontal, 8)

            // Explain / Context row
            HStack(spacing: 10) {
                Button {
                    guard session.ensureSignedIn() else { return }
                    showExplainSheet = true
                    isLoadingExplain = true
                    explainText = nil
                    Task {
                        let txt = await app.explain(sentence: sentence)
                        explainText = txt
                        isLoadingExplain = false
                    }
                } label: {
                    Label("Explain", systemImage: "questionmark.circle")
                        .font(.subheadline)
                }
                .buttonStyle(StablePillButtonStyle(height: 44))

                Button {
                    guard session.ensureSignedIn() else { return }
                    showContextSheet = true
                    isLoadingContext = true
                    contextText = nil
                    Task {
                        let txt = await app.contextualize(sentence: sentence)
                        contextText = txt
                        isLoadingContext = false
                    }
                } label: {
                    Label("Context", systemImage: "text.justify.left")
                        .font(.subheadline)
                }
                .buttonStyle(StablePillButtonStyle(height: 44))
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .padding(.top, 20)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: 420)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 8, x: 0, y: 4)

        // ✅ "Learned" toggle — stays in sync with Saved
        .overlay(alignment: .topTrailing) {
            Button {
                guard session.ensureSignedIn() else { return }
                Task {
                    let turnedOn = await learned.toggleLearned(sentence: sentence, language: mainLang)
                    // Make sure Saved tab mirrors this — on the main actor
                    await MainActor.run {
                        if turnedOn {
                            if !app.saved.contains(sentence.id) { app.toggleSave(sentence) }
                        } else {
                            if app.saved.contains(sentence.id) { app.toggleSave(sentence) }
                        }
                    }
                }
            } label: {
                let on = learned.isLearned(sentenceId: sentence.id, language: mainLang)
                Image(systemName: on ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(on ? .green : .secondary)
                    .padding(10)
                    .background(Color(.secondarySystemBackground).opacity(0.92), in: Circle())
                    .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                    .shadow(radius: 1, y: 1)
                    .accessibilityLabel(on ? "Learned" : "Mark learned")
                    .id(on) // 👈 force symbol to refresh when learned state changes
            }
            .padding(10)
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: showTranslation)
        .animation(.easeInOut(duration: 0.2), value: learned.learnedIDs)  // triggers the card to refresh

        // Explain sheet
        .sheet(isPresented: $showExplainSheet) {
            NavigationStack {
                Group {
                    if isLoadingExplain {
                        ProgressView("Explaining…")
                    } else if let t = explainText {
                        ScrollView { Text(t).padding() }
                    } else {
                        Text(app.aiError ?? "No explanation.")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Explanation")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showExplainSheet = false } } }
            }
            .presentationDetents([.medium, .large])
        }

        // Context sheet
        .sheet(isPresented: $showContextSheet) {
            NavigationStack {
                Group {
                    if isLoadingContext {
                        ProgressView("Building context…")
                    } else if let t = contextText {
                        ScrollView { Text(t).padding() }
                    } else {
                        Text(app.aiError ?? "No context.")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Context")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showContextSheet = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
