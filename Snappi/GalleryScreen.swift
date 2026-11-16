import SwiftUI
import AVKit

struct LibraryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var model: GalleryViewModel
    private var items: [CaptureItem] { model.items }
    @State private var selected: CaptureItem?
    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    ContentUnavailableView("Your moments live here", systemImage: "photo.on.rectangle.angled", description: Text("Take a photo, record a clip, or import an image to get started."))
                } else {
                    HStack {
                        Text("\(items.count) moments").font(.subheadline)
                        Spacer()
                        Text("Tap to open · swipe to explore").font(.caption)
                    }.foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(items) { item in
                        Button { selected = item } label: { MediaTile(item: item, repository: model.repository, height: 156) }
                            .buttonStyle(CameraPressStyle())
                            .accessibilityLabel("\(item.isVideo ? "Video" : "Photo"), \(item.date.formatted())")
                    }
                }.padding(.horizontal, 5)
            }.background(navy).navigationTitle("Your roll")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Camera") { dismiss() } } }
                .onAppear { model.reload() }
                .fullScreenCover(item: $selected) { item in MediaViewer(items: items, initialID: item.id, model: model) }
        }.tint(turquoise)
    }
}
struct MediaTile: View {
    let item: CaptureItem
    var height: CGFloat = 64
    @StateObject private var thumbnail: ThumbnailViewModel
    private var image: UIImage? { thumbnail.image }
    init(item: CaptureItem, repository: any MediaRepository, height: CGFloat = 64) {
        self.item = item; self.height = height
        _thumbnail = StateObject(wrappedValue: ThumbnailViewModel(item: item, repository: repository))
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Color.white.opacity(0.08)
                if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: height).clipped() }
                HStack(spacing: 3) {
                    if item.isVideo { Image(systemName: "play.fill") }
                    if item.isOriginal { Text("Original") }
                }.font(.system(size: 9, weight: .medium)).padding(5).shadow(color: .black, radius: 2)
            }
        }.frame(height: height).clipShape(RoundedRectangle(cornerRadius: 5))
            .task(id: item.id) { await thumbnail.load() }
    }
}
struct MediaViewer: View {
    let items: [CaptureItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: String
    @ObservedObject var model: GalleryViewModel
    init(items: [CaptureItem], initialID: String, model: GalleryViewModel) {
        self.items = items
        self.model = model
        _selection = State(initialValue: initialID)
    }
    private var index: Int { items.firstIndex { $0.id == selection } ?? 0 }
    private var current: CaptureItem? { items.indices.contains(index) ? items[index] : nil }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.25) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TabView(selection: $selection) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        Group {
                            // Keep only the current page and its neighbours decoded.
                            if abs(offset - index) <= 1 { MediaPage(item: item, active: selection == item.id, repository: model.repository) }
                            else { Color.black }
                        }.tag(item.id)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                    .accessibilityLabel("Captured photos and videos")
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(index == 0).accessibilityLabel("Previous capture")
                    Spacer()
                    VStack(spacing: 4) {
                        Text(current?.isOriginal == true ? "Original capture" : current?.isVideo == true ? "Video" : "Photo").font(.caption.weight(.medium))
                        Text(current?.isVideo == true ? "Swipe for the next moment" : "Swipe to browse · pinch to zoom")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(index == items.count - 1).accessibilityLabel("Next capture")
                }.padding(.horizontal, 14).buttonStyle(CameraPressStyle())
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 6) {
                            ForEach(items) { item in
                                Button { withAnimation(motion) { selection = item.id } } label: {
                                    MediaTile(item: item, repository: model.repository).frame(width: 48)
                                        .padding(3)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.id == selection ? turquoise : .clear, lineWidth: 2))
                                        .opacity(item.id == selection ? 1 : 0.65)
                                }.buttonStyle(CameraPressStyle()).id(item.id)
                                    .accessibilityLabel("\(item.isVideo ? "Video" : "Photo") \((items.firstIndex { $0.id == item.id } ?? 0) + 1)")
                                    .accessibilityAddTraits(item.id == selection ? .isSelected : [])
                            }
                        }.padding(.horizontal, 18).padding(.vertical, 3)
                    }.frame(height: 76)
                        .onAppear { proxy.scrollTo(selection, anchor: .center) }
                        .onChange(of: selection) { _, value in withAnimation(motion) { proxy.scrollTo(value, anchor: .center) } }
                }
                if let current {
                    HStack(spacing: 12) {
                        ShareLink(item: current.url) { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 48) }
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        Button {
                            model.export(current, number: index + 1)
                        } label: {
                            Label(model.exporting ? "Saving…" : "Save", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }.disabled(model.exporting).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Save current capture to Photos")
                    }.font(.subheadline.weight(.medium)).buttonStyle(CameraPressStyle()).padding(.horizontal, 18).padding(.bottom, 8)
                }
            }.background(Color.black).navigationTitle("\(index + 1) of \(items.count)").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Label("Your roll", systemImage: "chevron.left") } } }
                .sensoryFeedback(.selection, trigger: selection)
                .alert("Snappi", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
        }.tint(turquoise).preferredColorScheme(.dark)
    }
    private func move(_ delta: Int) {
        let next = index + delta
        guard items.indices.contains(next) else { return }
        withAnimation(motion) { selection = items[next].id }
    }
}
private struct MediaPage: View {
    let item: CaptureItem
    let active: Bool
    @Environment(\.scenePhase) private var phase
    @StateObject private var thumbnail: ThumbnailViewModel
    private var image: UIImage? { thumbnail.image }
    @State private var player: AVPlayer?
    init(item: CaptureItem, active: Bool, repository: any MediaRepository) {
        self.item = item; self.active = active
        _thumbnail = StateObject(wrappedValue: ThumbnailViewModel(item: item, repository: repository))
    }
    var body: some View {
        Group {
            if item.isVideo { VideoPlayer(player: player) }
            else if let image { ZoomablePhoto(image: image, active: active) }
            else { ProgressView().tint(turquoise).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: active) {
            if item.isVideo {
                player?.pause()
                player = active ? AVPlayer(url: item.url) : nil
            } else if image == nil {
                await thumbnail.load(maxPixelSize: 2400)
            }
        }
        .onChange(of: phase) { _, value in if value != .active { player?.pause() } }
        .onDisappear { player?.pause(); player = nil }
    }
}
/// Native pinch, pan and double-tap; at 1× the parent pager handles horizontal swipes.
private struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PhotoZoomScrollView {
        let scroll = PhotoZoomScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4
        scroll.showsVerticalScrollIndicator = false; scroll.showsHorizontalScrollIndicator = false
        scroll.bounces = false; scroll.bouncesZoom = true
        // At fit size, let the parent page view own horizontal drags. Pinch stays enabled.
        scroll.panGestureRecognizer.isEnabled = false
        scroll.imageView.contentMode = .scaleAspectFit
        scroll.imageView.isAccessibilityElement = true
        scroll.imageView.accessibilityLabel = "Photo"
        scroll.imageView.accessibilityHint = "Pinch or double-tap to zoom"
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(tap)
        return scroll
    }
    func updateUIView(_ scroll: PhotoZoomScrollView, context: Context) {
        context.coordinator.animate = !reduceMotion
        if scroll.imageView.image !== image { scroll.setZoomScale(1, animated: false); scroll.imageView.image = image }
        if !active { scroll.setZoomScale(1, animated: false) }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var animate = true
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? PhotoZoomScrollView)?.imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale > 1.01
        }
        @objc func doubleTap(_ tap: UITapGestureRecognizer) {
            guard let scroll = tap.view as? PhotoZoomScrollView else { return }
            if scroll.zoomScale > 1.01 { scroll.setZoomScale(1, animated: animate) }
            else {
                let point = tap.location(in: scroll.imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: animate)
            }
        }
    }
}
private final class PhotoZoomScrollView: UIScrollView {
    let imageView = UIImageView()
    private var previousSize: CGSize = .zero
    override init(frame: CGRect) { super.init(frame: frame); addSubview(imageView) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != previousSize {
            previousSize = bounds.size
            setZoomScale(1, animated: false)
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }
}
