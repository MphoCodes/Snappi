import SwiftUI
import AVKit

struct LibraryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var model: GalleryViewModel
    @State private var filter = GalleryFilter.all
    @State private var selecting = false
    @State private var marked: Set<String> = []
    @State private var opened: CaptureItem?
    @State private var position: String?
    @State private var confirmDelete = false
    @State private var pendingPermanentDeletion: Set<String> = []
    private var items: [CaptureItem] { model.captures(filter) }
    private var groups: [(day: Date, captures: [CaptureItem])] {
        Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(GalleryFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Label(filter.rawValue, systemImage: "line.3.horizontal.decrease.circle") }
                    Spacer()
                    Text(selecting ? "\(marked.count) selected" : "\(items.count) moments")
                        .foregroundStyle(.secondary)
                }.padding()
                if filter == .deleted {
                    let size = model.deletedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                    Text(size.map { "Storage used: \($0)" } ?? "Storage size unavailable")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal).padding(.bottom, 8)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        if items.isEmpty {
                            ContentUnavailableView(emptyTitle, systemImage: filter == .favorites ? "heart" : "photo.on.rectangle")
                        }
                        ForEach(groups, id: \.day) { group in
                            VStack(alignment: .leading) {
                                Text(group.day.formatted(date: .abbreviated, time: .omitted))
                                    .font(.headline).padding(.horizontal, 10)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                                    ForEach(group.captures) { item in
                                        Button {
                                            if selecting {
                                                if !marked.insert(item.id).inserted { marked.remove(item.id) }
                                            } else { position = item.id; opened = item }
                                        } label: {
                                            MediaTile(item: item, repository: model.repository, height: 136)
                                                .overlay(alignment: .topTrailing) {
                                                    if selecting || model.favorites.contains(item.id) {
                                                        Image(systemName: selecting ? (marked.contains(item.id) ? "checkmark.circle.fill" : "circle") : "heart.fill")
                                                            .padding(5).background(.black.opacity(0.55), in: Circle()).padding(4)
                                                    }
                                                }
                                        }.buttonStyle(CameraPressStyle()).id(item.id)
                                            .accessibilityLabel("\(item.isVideo ? "Video" : "Photo"), \(item.date.formatted())")
                                            .accessibilityAddTraits(marked.contains(item.id) ? .isSelected : [])
                                    }
                                }
                            }.padding(.horizontal, 4)
                        }
                    }
                    .fullScreenCover(item: $opened, onDismiss: {
                        if let position { proxy.scrollTo(position, anchor: .center) }
                    }) { item in
                        MediaViewer(filter: filter, initialID: item.id, model: model, position: $position)
                    }
                }
                if selecting && !marked.isEmpty {
                    HStack {
                        if filter == .deleted {
                            Button("Restore") { relocateSelection() }
                            Spacer()
                            Button("Delete Permanently", role: .destructive) { pendingPermanentDeletion = marked }
                        } else {
                            Button(marked.isSubset(of: model.favorites) ? "Unfavorite" : "Favorite") {
                                model.toggleFavorites(marked); endSelection()
                            }
                            Spacer()
                            Button("Delete", role: .destructive) { confirmDelete = true }
                        }
                    }.padding()
                }
            }
            .background(navy).navigationTitle("Your roll")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Camera") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "Done" : "Select") { if selecting { endSelection() } else { selecting = true } }
                        .disabled(items.isEmpty && !selecting)
                }
            }
            .onAppear { model.reload() }
            .onChange(of: filter) { endSelection() }
            .confirmationDialog("Move \(marked.count) to Recently Deleted?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Move to Recently Deleted", role: .destructive) { relocateSelection() }
            }
            .permanentDeletionConfirmation(ids: $pendingPermanentDeletion) { ids in
                model.permanentlyDelete(ids)
                marked.formIntersection(model.deleted.map(\.id))
                if marked.isEmpty { endSelection() }
            }
            .alert("Snappi", isPresented: Binding(get: { opened == nil && model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("OK") { model.message = nil }
            } message: { Text(model.message ?? "") }
        }.tint(turquoise)
    }
    private var emptyTitle: String {
        switch filter {
        case .all: return "Your roll is empty"
        case .photos: return "No photos yet"
        case .videos: return "No videos yet"
        case .favorites: return "No favorites yet"
        case .deleted: return "No deleted captures"
        }
    }
    private func relocateSelection() {
        model.relocate(items.filter { marked.contains($0.id) }, restoring: filter == .deleted)
        endSelection()
    }
    private func endSelection() { selecting = false; marked.removeAll() }
}
private extension View {
    func permanentDeletionConfirmation(ids: Binding<Set<String>>, delete: @escaping (Set<String>) -> Void) -> some View {
        let selection = ids.wrappedValue
        let captures = selection.count == 1 ? "1 capture" : "\(selection.count) captures"
        return confirmationDialog("Permanently delete \(captures)?", isPresented: Binding(
            get: { !ids.wrappedValue.isEmpty },
            set: { if !$0 { ids.wrappedValue = [] } }
        ), titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) { delete(selection) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can’t undo this in Snappi. Copies saved to Apple Photos stay there.")
        }
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
    let filter: GalleryFilter
    private var items: [CaptureItem] { model.captures(filter) }
    @Binding var position: String?
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingPermanentDeletion: Set<String> = []
    @State private var selection: String
    @ObservedObject var model: GalleryViewModel
    init(filter: GalleryFilter, initialID: String, model: GalleryViewModel, position: Binding<String?>) {
        self.filter = filter
        _position = position
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
                    HStack {
                        if filter == .deleted {
                            Button("Restore") { changeCurrent { model.relocate([current], restoring: true) } }
                            Spacer()
                            Button("Delete Permanently", role: .destructive) { pendingPermanentDeletion = [current.id] }
                        } else {
                            Button { changeCurrent { model.toggleFavorites([current.id]) } } label: {
                                action(model.favorites.contains(current.id) ? "Unfavorite" : "Favorite", model.favorites.contains(current.id) ? "heart.fill" : "heart")
                            }
                            ShareLink(item: current.url) { action("Share", "square.and.arrow.up") }
                            Button { model.export(current, number: index + 1) } label: {
                                action(model.exporting ? "Saving…" : "Save to Photos", "square.and.arrow.down")
                            }.disabled(model.exporting)
                            Button(role: .destructive) { confirmDelete = true } label: { action("Delete", "trash") }
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 8)
                    .confirmationDialog("Move to Recently Deleted?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Move to Recently Deleted", role: .destructive) {
                            changeCurrent { model.relocate([current], restoring: false) }
                        }
                    }
                }
            }.background(Color.black).navigationTitle("\(index + 1) of \(items.count)").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Label("Your roll", systemImage: "chevron.left") } } }
                .onChange(of: selection) { _, id in position = id }
                .sensoryFeedback(.selection, trigger: selection)
                .permanentDeletionConfirmation(ids: $pendingPermanentDeletion) { ids in
                    changeCurrent { model.permanentlyDelete(ids) }
                }
                .alert("Snappi", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
        }.tint(turquoise).preferredColorScheme(.dark)
    }
    private func action(_ title: String, _ icon: String) -> some View {
        VStack { Image(systemName: icon); Text(title).font(.caption) }
            .frame(maxWidth: .infinity, minHeight: 48)
    }
    private func changeCurrent(_ change: () -> Void) {
        let previous = index
        change()
        guard !items.contains(where: { $0.id == selection }) else { return }
        if items.isEmpty { position = nil; dismiss() }
        else { selection = items[min(previous, items.count - 1)].id; position = selection }
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
