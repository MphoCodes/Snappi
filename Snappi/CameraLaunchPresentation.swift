import Lottie
import SwiftUI

struct CameraLaunchPresentation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var finished = false

    let hasLivePreview: Bool
    private static let artwork = LottieAnimation.named("DaylightLaunch")

    func body(content: Content) -> some View {
        content
            .overlay {
                if !finished, !reduceMotion, !hasLivePreview, let artwork = Self.artwork {
                    ZStack {
                        navy.ignoresSafeArea()
                        LottieView(animation: artwork)
                            .playing(loopMode: .playOnce)
                            .animationDidFinish { completed in
                                if completed {
                                    withAnimation(.easeOut(duration: 0.16)) { finished = true }
                                }
                            }
                            .resizable()
                            .aspectRatio(artwork.size.width / artwork.size.height, contentMode: .fit)
                            .frame(maxWidth: 288)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                }
            }
            .onChange(of: reduceMotion, initial: true) { _, enabled in
                if enabled { finished = true }
            }
            .onChange(of: hasLivePreview, initial: true) { _, available in
                if available { finished = true }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { finished = true }
            }
    }
}
