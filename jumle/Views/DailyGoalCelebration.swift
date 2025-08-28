//
//  DailyGoalCelebration.swift - Option 3: Modal Card Style
//  jumle
//
//  Centered modal card celebration
//

import SwiftUI

// MARK: - Modal Card Style (Option 3)
struct DailyGoalCelebrationView: View {
    @State private var isVisible = false
    @State private var cardScale = 0.8
    @State private var rotateAngle = 0.0
    @State private var sparkleOpacity = 0.0
    
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Subtle background blur
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissModal()
                }
            
            // Modal card
            VStack(spacing: 28) {
                // Trophy section with sparkles
                ZStack {
                    // Sparkle background effect
                    ForEach(0..<8, id: \.self) { index in
                        Image(systemName: "sparkle")
                            .font(.caption)
                            .foregroundStyle(.orange.opacity(0.6))
                            .offset(sparkleOffset(for: index))
                            .opacity(sparkleOpacity)
                            .scaleEffect(sparkleOpacity)
                    }
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 90, height: 90)
                        .shadow(color: .orange.opacity(0.4), radius: 15, y: 8)
                    
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(rotateAngle))
                }
                
                // Text content
                VStack(spacing: 14) {
                    Text("🎉 Congratulations!")
                        .font(.title.bold())
                        .foregroundColor(.primary)
                    
                    Text("You've reached your daily goal!")
                        .font(.headline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    Text("Keep up the amazing work! 🚀")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .opacity(0.8)
                }
                .multilineTextAlignment(.center)
                
                // Action button
                Button(action: dismissModal) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Awesome!")
                        Image(systemName: "sparkles")
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .orange.opacity(0.3), radius: 8, y: 4)
                }
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 25, y: 15)
            )
            .scaleEffect(cardScale)
            .opacity(isVisible ? 1.0 : 0.0)
            .padding(.horizontal, 24)
        }
        .onAppear {
            startModalAnimation()
        }
    }
    
    private func sparkleOffset(for index: Int) -> CGSize {
        let angle = Double(index) * 45.0 // 8 sparkles, 45° apart
        let radius: CGFloat = 60
        let x = cos(angle * .pi / 180) * radius
        let y = sin(angle * .pi / 180) * radius
        return CGSize(width: x, height: y)
    }
    
    private func startModalAnimation() {
        // Modal entrance
        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
            isVisible = true
            cardScale = 1.0
        }
        
        // Trophy rotation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                rotateAngle = 360
            }
        }
        
        // Sparkles appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.8)) {
                sparkleOpacity = 1.0
            }
            
            // Sparkle twinkle effect
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                sparkleOpacity = 0.4
            }
        }
        
        // Auto-dismiss after 3.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            dismissModal()
        }
    }
    
    private func dismissModal() {
        withAnimation(.easeIn(duration: 0.3)) {
            isVisible = false
            cardScale = 0.8
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}
