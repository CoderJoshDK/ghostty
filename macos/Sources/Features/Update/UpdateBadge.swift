import SwiftUI

/// A badge view that displays the current state of an update operation.
///
/// Shows different visual indicators based on the update state:
/// - Progress ring for downloading/extracting with progress
/// - Animated rotating icon for checking/installing
/// - Static icon for other states
struct UpdateBadge: View {
    /// The update view model that provides the current state and progress
    @ObservedObject var model: UpdateViewModel
    
    /// Current rotation angle for animated icon states
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        switch model.state {
        case .downloading, .extracting:
            if let progress = model.progress {
                ProgressRingView(progress: progress)
            } else {
                Image(systemName: "arrow.down.circle")
            }
            
        case .checking, .installing:
            Image(systemName: model.iconName)
                .rotationEffect(.degrees(rotationAngle))
                .onAppear {
                    withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                        rotationAngle = 360
                    }
                }
                .onDisappear {
                    rotationAngle = 0
                }
            
        default:
            Image(systemName: model.iconName)
        }
    }
}

/// A circular progress indicator with a stroke-based ring design.
///
/// Displays a partially filled circle that represents progress from 0.0 to 1.0.
fileprivate struct ProgressRingView: View {
    /// The current progress value, ranging from 0.0 (empty) to 1.0 (complete)
    let progress: Double
    
    /// The width of the progress ring stroke
    let lineWidth: CGFloat = 2
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.2), lineWidth: lineWidth)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progress)
        }
    }
}
