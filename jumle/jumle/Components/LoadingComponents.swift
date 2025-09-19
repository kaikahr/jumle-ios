//
//  LoadingComponents.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-26.
//

//  Enhanced loading states and skeleton views

import SwiftUI
import UIKit


// MARK: - Loading Progress Bar
struct LoadingProgressBar: View {
    let progress: Double
    let isVisible: Bool
    
    var body: some View {
        if isVisible && progress > 0 {
            VStack(spacing: 4) {
                HStack {
                    Text("Loading content...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                        
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * progress)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct GrammarChipButton: View {
    let point: String
    let isSelected: Bool
    let isLoading: Bool
    let onSelect: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: isSelected ? .white : .blue))
                        .scaleEffect(0.7)
                } else if isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                }
                
                Text(point)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(
                    isSelected
                    ? Color.blue.opacity(0.25)
                    : Color.blue.opacity(isPressed ? 0.15 : 0.12)
                )
            )
            .foregroundStyle(.blue)
            .overlay(
                Capsule().stroke(Color.blue.opacity(0.35), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Smart Loading State Manager
struct SmartLoadingView<Content: View>: View {
    let loadingState: LoadingState
    let progress: Double
    let retryAction: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let emptyState: () -> ContentStateMessage
    
    var body: some View {
        switch loadingState {
        case .idle:
            content()
            
        case .loading:
            VStack(spacing: 16) {
                SkeletonCardView()
                
                LoadingProgressBar(
                    progress: progress,
                    isVisible: true
                )
                .padding(.horizontal)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            
        case .loaded:
            content()
                .transition(.opacity.combined(with: .scale(scale: 1.02, anchor: .center)))
            
        case .error(let message):
            VStack(spacing: 16) {
                ContentStateMessage(
                    title: "Failed to Load",
                    subtitle: message,
                    systemImage: "exclamationmark.triangle"
                )
                
                Button("Retry", action: retryAction)
                    .buttonStyle(StablePillButtonStyle())
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Content Transition Wrapper
struct ContentTransitionWrapper<Content: View>: View {
    let id: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        content()
            .id(id)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
    }
}

// MARK: - Haptic Feedback Helper
struct HapticFeedback {
    static func selectionChanged() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    static func success() {
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
    }
    
    static func error() {
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.error)
    }
}

// MARK: - Skeleton Card Loader
struct SkeletonCardView: View {
    @State private var animationPhase = 0.0
    
    var body: some View {
        VStack(spacing: 12) {
            // Topic chip skeleton
            HStack {
                Capsule()
                    .fill(shimmerGradient)
                    .frame(width: 80, height: 24)
                Spacer()
            }
            
            // Main text skeleton
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(height: 20)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(height: 20)
                    .scaleEffect(x: 0.8, anchor: .leading)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(height: 20)
                    .scaleEffect(x: 0.6, anchor: .leading)
            }
            .padding(.horizontal)
            
            // Button skeletons
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(shimmerGradient)
                        .frame(height: 42)
                }
            }
            .padding(.horizontal, 8)
            
            // Second row of buttons
            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { _ in
                    Capsule()
                        .fill(shimmerGradient)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, 20)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                animationPhase = 1.0
            }
        }
    }
    
    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.secondary.opacity(0.1),
                Color.secondary.opacity(0.3),
                Color.secondary.opacity(0.1)
            ],
            startPoint: UnitPoint(x: animationPhase - 0.3, y: 0.5),
            endPoint: UnitPoint(x: animationPhase + 0.3, y: 0.5)
        )
    }
}

// MARK: - Enhanced Theme Chips with Loading States
struct EnhancedThemeChips: View {
    let themes: [Theme]
    let selectedTheme: Theme
    let onSelect: (Theme) -> Void
    let loadingTheme: Theme?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(themes) { theme in
                    ThemeChipButton(
                        theme: theme,
                        isSelected: selectedTheme == theme,
                        isLoading: loadingTheme == theme,
                        onSelect: { onSelect(theme) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}

struct ThemeChipButton: View {
    let theme: Theme
    let isSelected: Bool
    let isLoading: Bool
    let onSelect: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: isSelected ? .white : .accentColor))
                        .scaleEffect(0.8)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.small)
                }
                
                Text(theme.display)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    isSelected
                    ? Color.accentColor
                    : Color.accentColor.opacity(isPressed ? 0.15 : 0.10)
                )
            )
            .foregroundStyle(isSelected ? .white : .accentColor)
            .overlay(
                Capsule().stroke(
                    Color.accentColor.opacity(isSelected ? 0 : 0.35),
                    lineWidth: 1
                )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Enhanced Grammar Chips
struct EnhancedGrammarChips: View {
    let points: [String]
    let selected: String?
    let onSelect: (String) -> Void
    let loadingGrammar: String?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(points, id: \.self) { point in
                    GrammarChipButton(
                        point: point,
                        isSelected: selected == point,
                        isLoading: loadingGrammar == point,
                        onSelect: { onSelect(point) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}
