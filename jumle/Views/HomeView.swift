// File: Views/HomeView.swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var learned: LearnedStore

    @State private var pageIndex: Int = 0
    @State private var showCongrats = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {

                // THEME selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Theme.allCases) { theme in
                            Button {
                                Task {
                                    app.selectedTheme = theme
                                    await app.loadTheme(theme)
                                    pageIndex = 0
                                }
                            } label: {
                                Text(theme.display)
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(
                                            app.selectedTheme == theme
                                            ? Color.accentColor.opacity(0.22)
                                            : Color.accentColor.opacity(0.10)
                                        )
                                    )
                                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.35)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }

                // GRAMMAR selector (same pattern as themes)
                GrammarChips(
                    
                    points: app.availableGrammar,
                    selected: app.selectedGrammar,
                    onSelect: { point in
                        let next = (app.selectedGrammar == point) ? nil : point
                        app.selectGrammar(next)
                        pageIndex = 0
                    }
                )
                .padding(.horizontal, 12)

                // ⬇️ Wrap the goal bar + pager with ZERO spacing and anchor the content to TOP
                VStack(spacing: 0) {
                    // DAILY GOAL
                    DailyGoalBar(count: learned.todayCount, goal: learned.dailyGoal)
                        .padding(.horizontal, 12)
                        .padding(.bottom, -16) // ← cancels any outer padding from the bar
                        .onChange(of: learned.todayCount) { old, new in
                            if old < learned.dailyGoal && new >= learned.dailyGoal {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                    showCongrats = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation(.easeOut) { showCongrats = false }
                                }
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if showCongrats {
                                HStack(spacing: 6) {
                                    Image(systemName: "party.popper.fill")
                                    Text("Great job!")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .padding(.trailing, 12)
                            }
                        }

                    // CONTENT
                    Group {
                        if app.isLoading && app.sentences.isEmpty {
                            ProgressView("Loading…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                        } else if let err = app.errorMessage, app.sentences.isEmpty {
                            VStack(spacing: 12) {
                                Text("Failed to load").font(.headline)
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                HBoxButtons
                            }
                            .padding()

                        } else if app.filtered.isEmpty {
                            VStack(spacing: 14) {
                                Text("No results").font(.headline)
                                Text("Try clearing search, topic, or grammar.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HBoxFilters
                                Button("Reload") {
                                    Task { await app.loadTheme(app.selectedTheme) }
                                }
                                .buttonStyle(StablePillButtonStyle())
                            }
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                        } else {
                            VStack(spacing: 0) {
                                TabView(selection: $pageIndex) {
                                    ForEach(Array(app.filtered.enumerated()), id: \.1.id) { idx, s in
                                        SentenceCardView(sentence: s)
                                            .environmentObject(app)
                                            .tag(idx)
                                            .padding(.horizontal, 12)
                                    }
                                }.offset(y: -40)
                                .tabViewStyle(.page(indexDisplayMode: .never))
                              //  .padding(.top, -16)          // ← nukes the page TabView top inset
                                .modifier(ZeroTabViewMargins())

                                Text("\(pageIndex + 1) / \(max(app.filtered.count, 1))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                    .padding(.bottom, 8)
                            }
                            .animation(.default, value: app.filtered.count)
                            .transition(.opacity)
                        }
                    }
                    // Make sure the whole content hugs the top edge of the available height.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .navigationTitle("Home")
        }
        .searchable(text: $app.searchText, placement: .navigationBarDrawer(displayMode: .always))
        .task {
            if app.sentences.isEmpty {
                await app.loadTheme(app.selectedTheme)
            }
        }
        .onChange(of: app.filtered) { _, new in
            if pageIndex >= new.count { pageIndex = max(0, new.count - 1) }
        }
        .onChange(of: app.searchText) { _, _ in pageIndex = 0 }
        .onChange(of: app.selectedTopic) { _, _ in pageIndex = 0 }
        .onChange(of: app.selectedGrammar) { _, _ in pageIndex = 0 }
    }

    // Small button rows extracted just to keep things readable
    private var HBoxButtons: some View {
        HStack {
            Button("Retry") {
                Task { await app.loadTheme(app.selectedTheme) }
            }
            .buttonStyle(StablePillButtonStyle())

            Button("Use Defaults") { app.errorMessage = nil }
                .buttonStyle(StablePillButtonStyle())
        }
    }

    private var HBoxFilters: some View {
        HStack(spacing: 10) {
            Button("Clear Search") { app.searchText = "" }
                .buttonStyle(StablePillButtonStyle())
            Button("Clear Topic") { app.selectedTopic = nil }
                .buttonStyle(StablePillButtonStyle())
            Button("Clear Grammar") { app.selectGrammar(nil) }
                .buttonStyle(StablePillButtonStyle())
        }
    }
}

// iOS 17+: strip TabView’s extra vertical margins.
// On older iOS this is a no-op.
private struct ZeroTabViewMargins: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentMargins(.vertical, 0)
        } else {
            content
        }
    }
}
