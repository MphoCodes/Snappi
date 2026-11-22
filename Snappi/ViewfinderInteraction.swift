import SwiftUI
import AVFoundation

enum ViewfinderDrag {
    case exposure, look

    static func direction(_ translation: CGPoint) -> Self? {
        let x = abs(translation.x), y = abs(translation.y)
        if x >= 10 && x > y * 1.3 { return .look }
        if y >= 10 && y > x * 1.3 { return .exposure }
        return nil
    }
}

struct PreviewGeometry {
    let imageRect: CGRect

    init(image: CGSize, view: CGSize) {
        guard image.width > 0, image.height > 0 else { imageRect = .zero; return }
        imageRect = AVMakeRect(aspectRatio: image, insideRect: CGRect(origin: .zero, size: view))
    }

    func unitPoint(_ touch: CGPoint) -> CGPoint? {
        guard imageRect.width > 0, imageRect.height > 0, imageRect.contains(touch) else { return nil }
        return CGPoint(x: (touch.x - imageRect.minX) / imageRect.width,
                       y: (touch.y - imageRect.minY) / imageRect.height)
    }
}

struct ViewfinderInteraction: UIViewRepresentable {
    var imageSize: CGSize
    var exposure: Double
    var canMeter: Bool
    var onFocus: (CGPoint, Bool) -> Void
    var onExposure: (Double) -> Void
    var onLook: (CGFloat) -> Void
    var onAdjusting: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let coordinator = context.coordinator
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tap))
        let hold = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.hold))
        let drag = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.drag))
        drag.maximumNumberOfTouches = 1
        tap.require(toFail: hold)
        tap.require(toFail: drag)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(drag)
        return view
    }

    @MainActor final class Coordinator: NSObject {
        var parent: ViewfinderInteraction
        private var direction: ViewfinderDrag?
        private var startingExposure = 0.0
        private var beganInImage = false
        init(_ parent: ViewfinderInteraction) { self.parent = parent }

        private func meter(_ gesture: UIGestureRecognizer, lock: Bool) {
            guard parent.canMeter, let view = gesture.view else { return }
            let geometry = PreviewGeometry(image: parent.imageSize, view: view.bounds.size)
            if let point = geometry.unitPoint(gesture.location(in: view)) { parent.onFocus(point, lock) }
        }
        @objc func tap(_ gesture: UITapGestureRecognizer) { meter(gesture, lock: false) }
        @objc func hold(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { meter(gesture, lock: true) }
        }
        @objc func drag(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let delta = gesture.translation(in: view)
            let geometry = PreviewGeometry(image: parent.imageSize, view: view.bounds.size)
            if gesture.state == .began {
                direction = nil
                startingExposure = parent.exposure
                let location = gesture.location(in: view)
                beganInImage = geometry.unitPoint(CGPoint(x: location.x - delta.x, y: location.y - delta.y)) != nil
            }
            if gesture.state == .cancelled || gesture.state == .failed {
                parent.onAdjusting(false)
                return
            }
            if direction == nil { direction = ViewfinderDrag.direction(delta) }
            switch direction {
            case .exposure where parent.canMeter && beganInImage:
                parent.onAdjusting(gesture.state != .ended)
                parent.onExposure(startingExposure - 4 * delta.y / max(geometry.imageRect.height, 1))
            case .look where gesture.state == .ended && abs(delta.x) >= 35:
                parent.onLook(delta.x)
            default: break
            }
            if gesture.state == .ended { parent.onAdjusting(false) }
        }
    }
}
