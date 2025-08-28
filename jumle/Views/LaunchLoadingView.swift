//
//  LaunchLoadingView.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-28.
//

//
//  LaunchLoadingView.swift
//  jumle
//
//  Beautiful launch loading animation with app branding
//

import SwiftUI

struct LaunchLoadingView: View {
    @State private var isAnimating = false
    @State private var rotationAngle = 0.0
    @State private var pulseScale = 1.0
    @State private var textOpacity = 0.0
    @State private var logoScale = 0.5
    @State private var showSubtitle = false
    @State private var dotCount = 0
    
    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Dynamic gradient background
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.3),
                    Color.blue.opacity(0.4),
                    Color.teal.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .overlay(
                // Subtle animated particles
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 8, height: 8)
                        .offset(
                            x: CGFloat.random(in: -100...100),
                            y: CGFloat.random(in: -200...200)
                        )
                        .scaleEffect(pulseScale)
                        .animation(
                            .easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.3),
                            value: pulseScale
                        )
                }
            )
            
            VStack(spacing: 40) {
                // Main logo/icon area
                ZStack {
                    // Outer rotating ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.purple, .blue, .teal, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(rotationAngle))
                        .opacity(0.6)
                    
                    // Inner pulsing circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 90, height: 90)
                        .scaleEffect(pulseScale * 0.9)
                        .blur(radius: 1)
                    
                    // App icon placeholder - you can replace with your actual app icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple, .teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)
                        
                        // "J" for Jumle - replace with your actual icon
                        Text("J")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(logoScale)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
                
                // App name and loading text
                VStack(spacing: 16) {
                    Text("Jumle")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue, .teal],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(textOpacity)
                    
                    if showSubtitle {
                        Text("Language Learning Made Simple")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .opacity(textOpacity * 0.8)
                    }
                    
                    // Loading dots animation
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                                .scaleEffect(dotCount == index ? 1.5 : 1.0)
                                .opacity(dotCount >= index ? 1.0 : 0.3)
                                .animation(
                                    .easeInOut(duration: 0.6),
                                    value: dotCount
                                )
                        }
                    }
                    .opacity(textOpacity)
                }
            }
        }
        .onAppear {
            startAnimations()
        }
        .onReceive(timer) { _ in
            // Cycle through loading dots
            withAnimation(.easeInOut(duration: 0.3)) {
                dotCount = (dotCount + 1) % 4 // 0, 1, 2, 3, 0...
            }
        }
    }
    
    private func startAnimations() {
        // Logo entrance
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            logoScale = 1.0
        }
        
        // Continuous rotation
        withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
        
        // Continuous pulse
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            pulseScale = 1.2
        }
        
        // Text fade in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 1.0)) {
                textOpacity = 1.0
            }
        }
        
        // Subtitle appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.8)) {
                showSubtitle = true
            }
        }
        
        // Start dot animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isAnimating = true
        }
    }
}

// MARK: - App State Manager for Launch

@MainActor
final class AppLaunchManager: ObservableObject {
    @Published var isLaunching = true
    @Published var hasCompletedInitialSetup = false
    
    private let minimumLoadingTime: TimeInterval = 2.5 // Minimum time to show loading
    private let maximumLoadingTime: TimeInterval = 8.0 // Maximum time before forcing completion
    
    func startLaunchSequence() {
        // Ensure minimum loading time for smooth UX
        let startTime = Date()
        
        Task {
            // Perform any necessary initialization
            await performInitialSetup()
            
            // Calculate remaining time to meet minimum
            let elapsed = Date().timeIntervalSince(startTime)
            let remainingTime = max(0, minimumLoadingTime - elapsed)
            
            if remainingTime > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
            }
            
            // Complete launch
            await completeLaunch()
        }
        
        // Safety timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + maximumLoadingTime) {
            if self.isLaunching {
                self.completeLaunchSync()
            }
        }
    }
    
    private func performInitialSetup() async {
        // Add any initialization logic here:
        // - Pre-load essential data
        // - Setup services
        // - Check authentication state
        // - Prepare core app state
        
        // Simulate initialization work
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        await MainActor.run {
            hasCompletedInitialSetup = true
        }
    }
    
    private func completeLaunch() async {
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.8)) {
                isLaunching = false
            }
        }
    }
    
    private func completeLaunchSync() {
        withAnimation(.easeOut(duration: 0.8)) {
            isLaunching = false
        }
    }
}

// MARK: - Updated App Structure

// Add this to your jumleApp.swift, replacing the existing App structure:

/*
@main
struct JumleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var launchManager = AppLaunchManager()
    
    // Your existing state objects
    @StateObject private var app = AppState()
    @StateObject private var session = SessionViewModel()
    @StateObject private var audio = AudioPlayerService()
    @StateObject private var learned = LearnedStore()
    @StateObject private var streaks = StreakService()

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main app content
                ContentView()
                    .environmentObject(app)
                    .environmentObject(session)
                    .environmentObject(audio)
                    .environmentObject(learned)
                    .environmentObject(streaks)
                    .onAppear {
                        setupServices()
                    }
                    .onChange(of: session.currentUser?.uid) { _, newUID in
                        setupServices()
                    }
                    .onChange(of: learned.todayCount) { oldCount, newCount in
                        // Check if daily goal was just reached
                        if newCount >= learned.dailyGoal && oldCount < learned.dailyGoal {
                            Task {
                                await streaks.recordDailyGoalReached(count: newCount, goal: learned.dailyGoal)
                            }
                        }
                    }
                    .sheet(isPresented: $session.showSignInSheet) {
                        SignInView()
                            .environmentObject(session)
                            .presentationDetents([.medium, .large])
                    }
                    .opacity(launchManager.isLaunching ? 0 : 1)
                
                // Launch loading overlay
                if launchManager.isLaunching {
                    LaunchLoadingView()
                        .transition(.opacity.combined(with: .scale(scale: 1.1)))
                        .zIndex(1)
                }
            }
            .onAppear {
                launchManager.startLaunchSequence()
            }
        }
    }
    
    private func setupServices() {
        if let uid = session.currentUser?.uid {
            learned.start(userId: uid)
            streaks.start(userId: uid)
        } else {
            learned.stop()
            streaks.stop()
        }
    }
}
*/

// MARK: - Alternative Minimal Loading Animation

struct MinimalLaunchLoadingView: View {
    @State private var isAnimating = false
    @State private var progress: Double = 0
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Simple logo
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(isAnimating ? 1.0 : 0.8)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                
                VStack(spacing: 16) {
                    Text("Jumle")
                        .font(.title.bold())
                        .opacity(isAnimating ? 1 : 0)
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * progress, height: 4)
                                .animation(.easeInOut(duration: 0.3), value: progress)
                        }
                    }
                    .frame(height: 4)
                    .frame(maxWidth: 200)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isAnimating = true
            }
            
            // Animate progress
            animateProgress()
        }
    }
    
    private func animateProgress() {
        let steps = [0.0, 0.3, 0.6, 0.8, 1.0]
        let intervals = [0.0, 0.5, 1.0, 1.8, 2.5]
        
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + intervals[index]) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    progress = step
                }
            }
        }
    }
}

#Preview("Launch Loading") {
    LaunchLoadingView()
}

#Preview("Minimal Loading") {
    MinimalLaunchLoadingView()
}
