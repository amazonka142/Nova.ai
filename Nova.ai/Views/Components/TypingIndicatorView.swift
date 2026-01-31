import SwiftUI

struct TypingIndicatorView: View {
    @State private var numberOfDots = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .scaleEffect(numberOfDots == index ? 1.0 : 0.6)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.2), value: numberOfDots)
            }
        }
        .padding(12)
        .background(Material.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            numberOfDots = 2 // Trigger animation state
        }
    }
}
