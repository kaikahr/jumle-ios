//
//  SubscriptionPaywallView.swift
//  jumle
//
//  Created by Kai Kahar on 2025-09-08.
//
//
//  Beautiful subscription paywall with feature comparison
//

import SwiftUI
import StoreKit

struct SubscriptionPaywallView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProduct: Product?
    @State private var showingTerms = false
    @State private var showingPrivacy = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Feature Comparison
                    featureComparisonSection
                    
                    // Pricing Options
                    pricingSection
                    
                    // Subscribe Button
                    subscribeButton
                    
                    // Footer
                    footerSection
                }
                .padding()
            }
            .background(backgroundGradient)
            .navigationTitle("Upgrade to Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("Restore") {
                        Task {
                            await subscriptionManager.restorePurchases()
                        }
                    }
                    .disabled(subscriptionManager.isLoading)
                }
            }
            .alert("Error", isPresented: .constant(subscriptionManager.errorMessage != nil)) {
                Button("OK") {
                    subscriptionManager.errorMessage = nil
                }
            } message: {
                Text(subscriptionManager.errorMessage ?? "")
            }
        }
        .onAppear {
            if let firstProduct = subscriptionManager.availableProducts.first {
                selectedProduct = firstProduct
            }
        }
    }
    
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.1),
                Color.purple.opacity(0.1),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 50))
                .foregroundStyle(.orange.gradient)
            
            Text("Unlock Full Learning Power")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            
            Text("Join thousands of learners achieving fluency faster with premium features")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var featureComparisonSection: some View {
        VStack(spacing: 16) {
            Text("Free vs Premium")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                FeatureRow(
                    title: "Daily Sentence Saves",
                    freeValue: "8 per day",
                    premiumValue: "Unlimited",
                    icon: "bookmark.fill"
                )
                
                FeatureRow(
                    title: "Audio Playback Speeds",
                    freeValue: "1x only",
                    premiumValue: "0.5x, 1x, 2x",
                    icon: "speaker.wave.2.fill"
                )
                
                FeatureRow(
                    title: "Daily Quizzes",
                    freeValue: "5 per day",
                    premiumValue: "Unlimited",
                    icon: "brain.head.profile"
                )
                
                FeatureRow(
                    title: "Flashcard Practice",
                    freeValue: "Unlimited",
                    premiumValue: "Unlimited",
                    icon: "rectangle.on.rectangle",
                    bothHave: true
                )
                
                FeatureRow(
                    title: "AI Explanations & Context",
                    freeValue: "Not available",
                    premiumValue: "Unlimited",
                    icon: "sparkles"
                )
                
                FeatureRow(
                    title: "Custom AI Lessons",
                    freeValue: "Not available",
                    premiumValue: "3 per day",
                    icon: "graduationcap.fill"
                )
                
                FeatureRow(
                    title: "Progress Tracking",
                    freeValue: "Basic streaks",
                    premiumValue: "Advanced analytics",
                    icon: "chart.line.uptrend.xyaxis"
                )
                
                FeatureRow(
                    title: "Offline Access",
                    freeValue: "Not available",
                    premiumValue: "Full offline mode",
                    icon: "arrow.down.circle.fill"
                )
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private var pricingSection: some View {
        VStack(spacing: 16) {
            Text("Choose Your Plan")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                ForEach(subscriptionManager.availableProducts, id: \.id) { product in
                    PricingCard(
                        product: product,
                        isSelected: selectedProduct?.id == product.id,
                        onSelect: { selectedProduct = product }
                    )
                }
            }
        }
    }
    
    private var subscribeButton: some View {
        VStack(spacing: 12) {
            Button {
                guard let product = selectedProduct else { return }
                Task {
                    do {
                        try await subscriptionManager.purchase(product)
                        dismiss()
                    } catch {
                        subscriptionManager.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    if subscriptionManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    Text("Start Premium")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(selectedProduct == nil || subscriptionManager.isLoading)
            
            Text("7-day free trial, then \(selectedProduct?.displayPrice ?? "$9.99")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var footerSection: some View {
        VStack(spacing: 12) {
            // Notes
            VStack(spacing: 8) {
                Text("• Cancel anytime in Settings")
                Text("• Auto-renewal can be turned off")
                Text("• Payment charged to iTunes Account")
            }
            .multilineTextAlignment(.center)

            // Links
            HStack(spacing: 24) {
                Button("Terms of Service") { showingTerms = true }
                Button("Privacy Policy") { showingPrivacy = true }
            }
            .tint(.blue) // color for the buttons
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .sheet(isPresented: $showingTerms) {
            SafariView(url: URL(string: "https://jumle.ai/terms")!)
        }
        .sheet(isPresented: $showingPrivacy) {
            SafariView(url: URL(string: "https://jumle.ai/privacy")!)
        }
    }

}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let title: String
    let freeValue: String
    let premiumValue: String
    let icon: String
    var bothHave: Bool = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Text("Free:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(freeValue)
                        .font(.caption)
                        .foregroundStyle(bothHave ? .green : .secondary)
                }
                
                HStack {
                    Text("Premium:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(premiumValue)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

// MARK: - Pricing Card Component
struct PricingCard: View {
    let product: Product
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var subscriptionProduct: SubscriptionProduct? {
        SubscriptionProduct(rawValue: product.id)
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subscriptionProduct?.displayName ?? "Premium")
                            .font(.headline)
                        
                        if let savings = subscriptionProduct?.savings {
                            Text(savings)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(product.displayPrice)
                            .font(.title2.bold())
                        
                        if subscriptionProduct == .annual {
                            Text("$6.67/month")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Safari View for Terms/Privacy
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
