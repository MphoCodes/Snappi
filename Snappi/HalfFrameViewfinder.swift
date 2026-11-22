import SwiftUI

struct HalfFrameViewfinder: View {
    let live: UIImage
    let first: UIImage?
    let grid: Bool

    var body: some View {
        GeometryReader { area in
            let panelWidth = area.size.width / 2
            HStack(spacing: 0) {
                panel(first ?? live, number: 1, live: first == nil, size: CGSize(width: panelWidth, height: area.size.height))
                panel(first == nil ? nil : live, number: 2, live: first != nil, size: CGSize(width: panelWidth, height: area.size.height))
            }
            .overlay { Rectangle().fill(.black.opacity(0.7)).frame(width: 1) }
        }
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
    }

    private func panel(_ image: UIImage?, number: Int, live: Bool, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.white.opacity(0.08)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
                    .overlay { if grid && live { GridOverlay() } }
            }
            Text("Frame \(number)").font(.caption2.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(.black.opacity(0.65), in: Capsule()).padding(7)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Frame \(number), \(live ? "live camera" : image == nil ? "waiting" : "captured")")
    }
}
