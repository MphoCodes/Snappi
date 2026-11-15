import SwiftUI

extension FilmLook {
    var character: String {
        switch self {
        case .original: return "Just as you see it"
        case .daylight: return "Clean light. Soft colour."
        case .golden: return "A little late-afternoon warmth"
        case .faded: return "Soft tones. Old memories."
        case .noir: return "Light, shadow, nothing else"
        case .tape: return "A softer kind of motion"
        }
    }
    var stock: String {
        switch self {
        case .original: return "TRUE"
        case .daylight: return "DAY"
        case .golden: return "SUN"
        case .faded: return "FADE"
        case .noir: return "B&W"
        case .tape: return "PLAY"
        }
    }
}

/// One small press response, shared by the camera controls. Never delays the action.
struct CameraPressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
struct ViewfinderButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
struct FilmPreview: View {
    let look: FilmLook
    let image: UIImage?
    let selected: Bool
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottomLeading) {
                Color.white.opacity(0.055)
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else {
                    Image(systemName: look == .tape ? "video" : "camera.aperture")
                        .font(.system(size: 18, weight: .ultraLight)).foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(look.stock).font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(1)
                    .padding(.horizontal, 4).padding(.vertical, 3)
                    .background(.black.opacity(0.7)).padding(4)
            }.frame(width: 59, height: 57).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.13), lineWidth: 1)
                    if selected { RoundedRectangle(cornerRadius: 8).stroke(turquoise, lineWidth: 2).matchedGeometryEffect(id: "filmSelection", in: namespace) }
                }
            Text(look.rawValue).font(.system(size: 10, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? turquoise : .white.opacity(0.55))
        }.frame(width: 65)
            .scaleEffect(selected && !reduceMotion ? 1.04 : 1)
            .offset(y: selected && !reduceMotion ? -2 : 0)
            .accessibilityElement(children: .ignore)
    }
}
struct ShutterFace: View {
    let video: Bool
    let recording: Bool
    let start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !recording)) { timeline in
            ZStack {
                Circle().stroke(.white.opacity(recording ? 0.2 : 0.85), lineWidth: 2.5)
                Circle().stroke(.white.opacity(0.12), lineWidth: 1).padding(5)
                if recording, let start {
                    Circle().trim(from: 0, to: min(max(timeline.date.timeIntervalSince(start) / 60, 0), 1))
                        .stroke(.red, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                RoundedRectangle(cornerRadius: recording ? 7 : 31)
                    .fill(video ? Color(red: 0.96, green: 0.28, blue: 0.24) : Color(red: 0.95, green: 0.95, blue: 0.9))
                    .frame(width: recording ? 28 : 62, height: recording ? 28 : 62)
            }.frame(width: 78, height: 78)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: recording)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: video)
        }.accessibilityHidden(true)
    }
}
struct RecordingReadout: View {
    let start: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: reduceMotion)) { timeline in
            HStack(spacing: 7) {
                Circle().fill(.red).frame(width: 6, height: 6)
                    .opacity(reduceMotion || Int(timeline.date.timeIntervalSince(start) * 2) % 2 == 0 ? 1 : 0.4)
                Text("REC").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                Text(start, style: .timer).font(.system(size: 12, weight: .medium, design: .monospaced)).monospacedDigit().fixedSize()
            }.padding(.horizontal, 12).padding(.vertical, 9).background(.black.opacity(0.75), in: Capsule())
        }.accessibilityElement(children: .combine)
    }
}
