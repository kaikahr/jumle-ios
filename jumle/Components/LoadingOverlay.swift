//
//  LoadingOverlay.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-28.
//

//
//  LoadingOverlay.swift
//  jumle
//
//  Full-screen loading overlay that blocks user interaction
//

import SwiftUI

struct LoadingOverlay: View {
    let isVisible: Bool
    let message: String
    
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: Double = 1.0
    
    var body: some View {
        if isVisible {
            ZStack {
                // Semi-transparent background that blocks interaction
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                // Loading content
                VStack(spacing: 20) {
                    // Animated loading icon
                    ZStack {
                        // Outer ring
                        Circle()
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 6)
                            .frame(width: 80, height: 80)
                        
                        // Animated arc
                        Circle()
                            .trim(from: 0.0, to: 0.75)
                            .stroke(
                                Color.accentColor,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(rotationAngle))
                            .animation(
                                .linear(duration: 1.0).repeatForever(autoreverses: false),
                                value: rotationAngle
                            )
                        
                        // Center dot with pulse animation
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 16, height: 16)
                            .scaleEffect(pulseScale)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: pulseScale
                            )
                    }
                    
                    // Loading message
                    Text(message)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    // Animated dots
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color.secondary)
                                .frame(width: 8, height: 8)
                                .scaleEffect(pulseScale)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                    value: pulseScale
                                )
                        }
                    }
                }
                .padding(40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .onAppear {
                rotationAngle = 360
                pulseScale = 1.2
            }
        }
    }
}

// Alternative simpler loading overlay
struct SimpleLoadingOverlay: View {
    let isVisible: Bool
    let message: String
    
    @State private var isAnimating = false
    
    var body: some View {
        if isVisible {
            ZStack {
                // Background overlay
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                // Loading card
                VStack(spacing: 24) {
                    // Large system loading indicator
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                        .scaleEffect(2.0)
                        .frame(height: 60)
                    
                    Text(message)
                        .font(.title3.weight(.medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0.0)
            }
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isAnimating = true
                }
            }
            .onDisappear {
                isAnimating = false
            }
        }
    }
}

// Usage wrapper for your existing loading states
struct LoadingStateWrapper<Content: View>: View {
    let loadingState: LoadingState
    let loadingMessage: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        ZStack {
            content()
                .disabled(loadingState.isLoading)
                .blur(radius: loadingState.isLoading ? 2 : 0)
                .animation(.easeInOut(duration: 0.2), value: loadingState.isLoading)
            
            SimpleLoadingOverlay(
                isVisible: loadingState.isLoading,
                message: loadingMessage
            )
        }
    }
}
