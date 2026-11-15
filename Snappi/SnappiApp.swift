import SwiftUI
import PhotosUI
import AVKit
import Combine

private let navy = Color(red: 0.025, green: 0.065, blue: 0.11)
private let turquoise = Color(red: 0.16, green: 0.83, blue: 0.82)

@main
struct SnappiApp: App {
    var body: some Scene { WindowGroup { CameraScreen().preferredColorScheme(.dark) } }
}
struct CameraScreen: View {
    @StateObject private var camera = CameraController()
    @Environment(\.scenePhase) private var phase
    @AppStorage("look") private var selectedLook = FilmLook.daylight.rawValue
    @AppStorage("strength") private var strength = 0.8
    @AppStorage("grain") private var grain = 0.12
    @AppStorage("warmth") private var warmth = 0.0
    @AppStorage("dateStamp") private var dateStamp = false
    @AppStorage("keepOriginal") private var keepOriginal = false
    @AppStorage("exportPhotos") private var exportPhotos = true
    @AppStorage("grid") private var grid = false
    @State private var mode = "PHOTO"
    @State private var flash = false
    @State private var exposure = 0.0
    @State private var zoom = 1.0
    @State private var timerDelay = 0
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var showSettings = false
    @State private var showGallery = false
    @State private var showAdjustments = false
    @State private var imported: PhotosPickerItem?
    var settings: LookSettings { LookSettings(look: FilmLook(rawValue: selectedLook) ?? .daylight, strength: strength, grain: grain, warmth: warmth, dateStamp: dateStamp) }
    var locked: Bool { camera.busy || countdown > 0 }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image("BrandMark").resizable().scaledToFit().frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("snappi").font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-1)
                    Spacer()
                    Button { showSettings = true } label: { Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44) }.accessibilityLabel("Settings").disabled(locked)
                }.padding(.horizontal, 22)
                ZStack {
                    RoundedRectangle(cornerRadius: 26).fill(Color.black)
                    if let preview = camera.preview {
                        Image(uiImage: preview).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 26))
                    } else {
                        VStack(spacing: 15) {
                            Image(systemName: "camera.aperture").font(.system(size: 46)).foregroundStyle(turquoise)
                            Text(camera.status).font(.headline).multilineTextAlignment(.center)
                            if camera.denied {
                                Button("Open Settings") { openSettings() }.buttonStyle(.borderedProminent)
                            } else { Text("Your next favourite moment starts here.").font(.caption).foregroundStyle(.secondary) }
                        }.padding(30)
                    }
                    if grid { GridOverlay().allowsHitTesting(false) }
                    VStack {
                        HStack {
                            Text(settings.look.rawValue.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).padding(10).background(.black.opacity(0.45), in: Capsule())
                            Spacer()
                            if camera.recording, let start = camera.recordingStarted {
                                HStack(spacing: 6) { Circle().fill(.red).frame(width: 7, height: 7); Text(start, style: .timer).monospacedDigit() }.font(.caption.bold()).padding(10).background(.black.opacity(0.65), in: Capsule())
                            }
                        }
                        Spacer()
                        HStack {
                            if dateStamp { Text(Date.now.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits))).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(.orange.opacity(0.85)) }
                            Spacer()
                            Button { zoom = zoom == 1 ? 2 : (zoom == 2 ? 3 : 1); camera.zoom(zoom) } label: { Text("\(Int(zoom))×").font(.caption.bold()).frame(width: 40, height: 40).background(.black.opacity(0.6), in: Circle()) }.disabled(locked).accessibilityLabel("Digital zoom \(Int(zoom)) times")
                        }
                    }.padding(16)
                    if countdown > 0 { Text("\(countdown)").font(.system(size: 80, weight: .light, design: .rounded)).shadow(radius: 10) }
                    if camera.busy && !camera.recording { ProgressView().controlSize(.large).padding(22).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)) }
                }.frame(height: max(200, geometry.size.height - 315)).padding(.horizontal, 14)
                HStack(spacing: 26) {
                    Button { flash.toggle(); if mode == "VIDEO" { camera.torch(flash) } } label: { Image(systemName: flash ? "bolt.fill" : "bolt.slash").foregroundStyle(flash ? turquoise : .white) }.disabled(locked || !camera.flashAvailable).accessibilityLabel(mode == "VIDEO" ? "Video torch" : "Photo flash")
                    Button { timerDelay = timerDelay == 0 ? 3 : (timerDelay == 3 ? 10 : 0) } label: { HStack(spacing: 4) { Image(systemName: "timer"); if timerDelay > 0 { Text("\(timerDelay)s").font(.caption) } } }.disabled(locked).accessibilityLabel("Timer \(timerDelay) seconds")
                    Button { showAdjustments.toggle() } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(showAdjustments ? turquoise : .white) }.disabled(locked).accessibilityLabel("Adjust look and exposure")
                    Button { camera.switchCamera(); zoom = 1; exposure = 0; flash = false } label: { Image(systemName: "arrow.triangle.2.circlepath.camera") }.disabled(locked).accessibilityLabel("Switch front and rear camera")
                }.font(.system(size: 19)).frame(height: 30)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(FilmLook.allCases) { look in
                            Button { selectedLook = look.rawValue } label: {
                                Text(look.rawValue).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 11)
                                    .background(selectedLook == look.rawValue ? turquoise : Color.white.opacity(0.07), in: Capsule())
                                    .foregroundStyle(selectedLook == look.rawValue ? navy : Color.white.opacity(0.8))
                            }.disabled(locked)
                        }
                    }.padding(.horizontal, 20)
                }
                HStack(spacing: 25) {
                    ForEach(["PHOTO", "VIDEO"], id: \.self) { item in Button { mode = item; flash = false; camera.torch(false) } label: { Text(item).font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(mode == item ? turquoise : .gray) }.disabled(locked) }
                }
                HStack {
                    Button { showGallery = true } label: { Image(systemName: "square.stack").font(.title2).frame(width: 60, height: 60).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18)) }.accessibilityLabel("Snappi library").disabled(locked)
                    Spacer()
                    Button { shutter() } label: {
                        ZStack {
                            Circle().stroke(.white.opacity(0.9), lineWidth: 3).frame(width: 76, height: 76)
                            if camera.recording { RoundedRectangle(cornerRadius: 7).fill(.red).frame(width: 30, height: 30) }
                            else { Circle().fill(mode == "VIDEO" ? Color.red : Color.white).frame(width: 62, height: 62) }
                        }
                    }.disabled((!camera.ready || camera.busy) && !camera.recording || countdown > 0).accessibilityLabel(camera.recording ? "Stop recording" : mode == "VIDEO" ? "Record video" : "Take photo")
                    Spacer()
                    PhotosPicker(selection: $imported, matching: .images) { Image(systemName: "photo.badge.plus").font(.title2).frame(width: 60, height: 60).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18)) }.disabled(locked).accessibilityLabel("Import a photo")
                }.padding(.horizontal, 30)
                Text(countdown > 0 ? "Get ready…" : camera.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center).padding(.horizontal)
            }.padding(.top, 4).padding(.bottom, 6).frame(maxWidth: .infinity, maxHeight: .infinity).background(navy)
        }
        .tint(turquoise).foregroundStyle(.white)
        .onAppear { sync(); camera.start() }
        .onChange(of: settings) { _, _ in sync() }
        .onChange(of: keepOriginal) { _, _ in sync() }
        .onChange(of: exportPhotos) { _, _ in sync() }
        .onChange(of: phase) { _, value in
            if value == .active { camera.resume() }
            else if value == .background { countdownTask?.cancel(); countdown = 0; flash = false; camera.suspend() }
        }
        .onChange(of: imported) { _, item in
            guard let item else { return }
            Task {
                do { guard let data = try await item.loadTransferable(type: Data.self) else { throw MediaLibrary.failure("The selected photo could not be imported.") }; camera.importPhoto(data) }
                catch { camera.error = error.localizedDescription }
                imported = nil
            }
        }
        .sheet(isPresented: $showGallery) { LibraryScreen() }
        .sheet(isPresented: $showAdjustments) {
            NavigationStack {
                Form {
                    Section("Look") {
                        control("Strength", value: $strength, range: 0...1)
                        control("Film grain", value: $grain, range: 0...1)
                        control("Warmth", value: $warmth, range: -1...1)
                    }
                    Section { Slider(value: $exposure, in: -2...2).onChange(of: exposure) { _, value in camera.exposure(Float(value)) }; Text("Exposure \(exposure, specifier: "%+.1f") EV").font(.caption).monospacedDigit() } header: { Text("Camera exposure") }
                    Button("Reset adjustments") { strength = 0.8; grain = 0.12; warmth = 0; exposure = 0; camera.exposure(0) }
                }.navigationTitle("Make it yours").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAdjustments = false } } }
            }.presentationDetents([.medium, .large]).tint(turquoise)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("Capture") { Toggle("Composition grid", isOn: $grid); Toggle("Date stamp", isOn: $dateStamp); Toggle("Keep originals", isOn: $keepOriginal) }
                    Section { Toggle("Also save to Photos", isOn: $exportPhotos); Button("iPhone permissions") { openSettings() } } header: { Text("Your library") } footer: { Text("Captures always stay in Snappi. Photos access is optional. Deleting Snappi also deletes its local library—export any photos and videos you want to keep.") }
                    Section("Video") { Text("Portrait · up to 1080p · 60 seconds per clip"); Text("Your look is applied after recording. Keep Snappi open while it develops. Microphone permission is requested when you first record; without it, video is silent.").font(.footnote).foregroundStyle(.secondary) }
                    Section("Snappi 1.0") { Text("Photo + film. Yours to make.").font(.headline); Text("Six original looks. No accounts, ads or subscriptions. Everything is processed on your iPhone.").font(.footnote).foregroundStyle(.secondary) }
                }.navigationTitle("Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
            }.tint(turquoise)
        }
        .alert("Snappi", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) { Button("OK") { camera.error = nil } } message: { Text(camera.error ?? "") }
    }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View { VStack(alignment: .leading) { Text(title).font(.subheadline); Slider(value: value, in: range) } }
    private func sync() { camera.update(settings: settings, preserve: keepOriginal, export: exportPhotos) }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
    private func shutter() {
        if camera.recording { camera.stopVideo(); flash = false; return }
        countdownTask = Task { @MainActor in
            if timerDelay > 0 {
                for remaining in stride(from: timerDelay, through: 1, by: -1) {
                    countdown = remaining
                    do { try await Task.sleep(for: .seconds(1)) } catch { countdown = 0; return }
                }
                countdown = 0
            }
            guard !Task.isCancelled else { return }
            if mode == "VIDEO" { camera.startVideo() } else { camera.capturePhoto(flash: flash) }
        }
    }
}
struct GridOverlay: View {
    var body: some View { GeometryReader { g in Path { path in
        for n in 1...2 {
            let x = g.size.width * CGFloat(n) / 3, y = g.size.height * CGFloat(n) / 3
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: g.size.height))
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: g.size.width, y: y))
        }
    }.stroke(.white.opacity(0.3), lineWidth: 0.5) } }
}
struct LibraryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CaptureItem] = []
    @State private var selected: CaptureItem?
    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty { ContentUnavailableView("Your moments live here", systemImage: "photo.on.rectangle.angled", description: Text("Take a photo, record a clip, or import an image to get started.")) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                    ForEach(items) { item in Button { selected = item } label: { MediaTile(item: item) }.buttonStyle(.plain) }
                }.padding(6)
            }.background(navy).navigationTitle("Your roll")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { items = MediaLibrary.items() }
                .sheet(item: $selected) { MediaDetail(item: $0) }
        }.tint(turquoise)
    }
}
struct MediaTile: View {
    let item: CaptureItem
    @State private var image: UIImage?
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.white.opacity(0.08)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            HStack { if item.isVideo { Image(systemName: "play.fill") }; if item.isOriginal { Text("Original").font(.caption2) } }.padding(7).shadow(radius: 3)
        }.frame(height: 150).clipped().clipShape(RoundedRectangle(cornerRadius: 8)).task { image = await MediaLibrary.thumbnail(item) }
    }
}
struct MediaDetail: View {
    let item: CaptureItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var message: String?
    @State private var exporting = false
    var body: some View {
        NavigationStack {
            VStack {
                if item.isVideo { VideoPlayer(player: player).onAppear { player = AVPlayer(url: item.url) }.onDisappear { player?.pause(); player = nil } }
                else if let image = UIImage(contentsOfFile: item.url.path) { Image(uiImage: image).resizable().scaledToFit() }
                Spacer(minLength: 8)
                HStack(spacing: 30) {
                    ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { exporting = true; Task { do { try await MediaLibrary.saveToPhotos(item.url); message = "Saved to Photos" } catch { message = error.localizedDescription }; exporting = false } } label: { Label(exporting ? "Saving…" : "Save to Photos", systemImage: "square.and.arrow.down") }.disabled(exporting)
                }.padding()
            }.background(navy).navigationTitle(item.isOriginal ? "Original capture" : "Made with Snappi").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .alert("Snappi", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
        }.tint(turquoise)
    }
}
