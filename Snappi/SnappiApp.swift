import SwiftUI
import PhotosUI
import AVKit
import Combine

let navy = Color(red: 0.025, green: 0.065, blue: 0.11)
let turquoise = Color(red: 0.16, green: 0.83, blue: 0.82)

@main
struct SnappiApp: App {
    private let services = AppServices.live()
    var body: some Scene { WindowGroup { CameraScreen(services: services).preferredColorScheme(.dark) } }
}
struct CameraScreen: View {
    @StateObject private var camera: CameraViewModel
    private let services: AppServices
    init(services: AppServices) {
        self.services = services
        _camera = StateObject(wrappedValue: services.cameraViewModel())
    }
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    private var latestThumbnail: UIImage? { camera.latestThumbnail }
    private var rollCount: Int { camera.rollCount }
    @State private var savedPulse = false
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
    private var countdown: Int { camera.countdown }
    @State private var showSettings = false
    @State private var showGallery = false
    @State private var showAdjustments = false
    @State private var imported: PhotosPickerItem?
    var settings: LookSettings { LookSettings(look: FilmLook(rawValue: selectedLook) ?? .daylight, strength: strength, grain: grain, warmth: warmth, dateStamp: dateStamp) }
    var locked: Bool { camera.busy || countdown > 0 }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                header
                viewfinder
                    .frame(height: max(180, geometry.size.height - 342))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 12)
                filmTray
                modeSelector
                captureBar
                Text(countdown > 0 ? "Get ready…" : camera.status)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2).multilineTextAlignment(.center).frame(minHeight: 26)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 2).padding(.bottom, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(navy.ignoresSafeArea())
        }
        .tint(turquoise).foregroundStyle(.white)
        .onAppear { sync(); camera.start() }
        .task(id: camera.latest) { await refreshRoll() }
        .sensoryFeedback(.selection, trigger: selectedLook)
        .sensoryFeedback(.selection, trigger: mode)
        .sensoryFeedback(.selection, trigger: timerDelay)
        .sensoryFeedback(.success, trigger: camera.latest)
        .sensoryFeedback(.impact(weight: .light), trigger: countdown)
        .onChange(of: settings) { _, _ in sync() }
        .onChange(of: keepOriginal) { _, _ in sync() }
        .onChange(of: exportPhotos) { _, _ in sync() }
        .onChange(of: phase) { _, value in
            if value == .active { camera.resume() }
            else if value == .background { flash = false; camera.suspend() }
        }
        .onChange(of: imported) { _, item in
            guard let item else { return }
            Task { await camera.importSelection(item); imported = nil }
        }
        .sheet(isPresented: $showGallery, onDismiss: { Task { await camera.refreshRoll() } }) { LibraryScreen(model: services.galleryViewModel()) }

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
                    Section("Snappi 1.1") { Text("Photo + film. Yours to make.").font(.headline); Text("Six original looks. No accounts, ads or subscriptions. Everything is processed on your iPhone.").font(.footnote).foregroundStyle(.secondary) }
                }.navigationTitle("Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
            }.tint(turquoise)
        }
        .alert("Snappi", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) { Button("OK") { camera.error = nil } } message: { Text(camera.error ?? "") }
    }
    private var motion: Animation? { reduceMotion ? nil : .easeOut(duration: 0.22) }
    private var header: some View {
        HStack(spacing: 8) {
            Image("BrandMark").resizable().scaledToFit().frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
            Text("snappi").font(.system(size: 24, weight: .semibold, design: .rounded)).tracking(-1)
            Spacer()
            Text("PHOTO + FILM").font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.3).foregroundStyle(.white.opacity(0.45))
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 18)).frame(width: 44, height: 44)
            }.buttonStyle(CameraPressStyle()).accessibilityLabel("Settings").disabled(locked)
        }.padding(.leading, 20).padding(.trailing, 10).frame(height: 40)
    }
    private var viewfinder: some View {
        ZStack {
            Color.black
            if mode == "PAIR", let preview = camera.preview {
                HalfFrameViewfinder(live: preview, first: camera.firstHalfFrame?.preview, grid: grid)
            } else if let preview = camera.preview {
                Image(uiImage: preview).resizable().scaledToFit()
                    .overlay { if grid { GridOverlay() } }
                    .accessibilityLabel("Live camera preview")
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "camera.aperture").font(.system(size: 38, weight: .ultraLight))
                        .foregroundStyle(turquoise)
                    Text(camera.status).font(.subheadline).multilineTextAlignment(.center)
                    if camera.denied { Button("Open Settings") { openSettings() }.buttonStyle(.bordered) }
                }.padding(40)
            }
            VStack {
                HStack(spacing: 4) {
                    Button { flash.toggle(); if mode == "VIDEO" { camera.torch(flash) } } label: {
                        VStack(spacing: 5) {
                            Image(systemName: flash ? "bolt.fill" : "bolt.slash")
                            Text("\(mode == "VIDEO" ? "Torch" : "Flash") \(flash ? "On" : "Off")").font(.system(size: 10, weight: .medium))
                        }.foregroundStyle(flash ? turquoise : .white).frame(width: 70, height: 52)
                    }.disabled(locked || !camera.flashAvailable)
                        .accessibilityLabel(mode == "VIDEO" ? "Video torch" : "Photo flash").accessibilityValue(flash ? "On" : "Off")
                    Button { timerDelay = timerDelay == 0 ? 3 : (timerDelay == 3 ? 10 : 0) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "timer")
                            Text(timerDelay > 0 ? "Timer \(timerDelay)s" : "Timer Off").font(.system(size: 10, weight: .medium))
                        }.frame(width: 70, height: 52)
                    }.disabled(locked).accessibilityLabel("Timer \(timerDelay) seconds")
                    Spacer()
                    Button { camera.switchCamera(); zoom = 1; exposure = 0; flash = false } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .rotationEffect(.degrees(camera.isFront && !reduceMotion ? 180 : 0))
                                .animation(motion, value: camera.isFront)
                            Text("Flip").font(.system(size: 10, weight: .medium))
                        }.frame(width: 60, height: 52)
                    }.disabled(locked).accessibilityLabel("Switch front and rear camera")
                }.font(.system(size: 18)).buttonStyle(ViewfinderButtonStyle())
                Spacer()
                if camera.recording, let start = camera.recordingStarted {
                    RecordingReadout(start: start).transition(.opacity)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(settings.look.rawValue.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.8)
                        if dateStamp {
                            Text(Date.now.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits)))
                                .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.orange)
                        }
                    }.padding(10).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
                    Spacer()
                    Button { zoom = zoom == 1 ? 2 : (zoom == 2 ? 3 : 1); camera.zoom(zoom) } label: {
                        Text("\(Int(zoom))× Zoom").font(.system(size: 12, weight: .semibold)).contentTransition(.numericText())
                            .frame(width: 82, height: 44)
                    }.buttonStyle(ViewfinderButtonStyle()).disabled(locked)
                        .accessibilityLabel("Digital zoom \(Int(zoom)) times")
                        .animation(motion, value: zoom)
                }
            }.padding(10)
            if countdown > 0 {
                Text("\(countdown)").font(.system(size: 88, weight: .ultraLight, design: .rounded))
                    .contentTransition(.numericText(countsDown: true)).animation(motion, value: countdown)
                    .padding(28).background(.black.opacity(0.35), in: Circle()).accessibilityLabel("\(countdown) seconds")
            }
            Color.white
                .keyframeAnimator(initialValue: 0.0, trigger: camera.photoCaptured) { content, opacity in
                    content.opacity(opacity)
                } keyframes: { _ in
                    MoveKeyframe(0.65)
                    LinearKeyframe(0, duration: 0.24)
                }.opacity(reduceMotion ? 0 : 1).allowsHitTesting(false).accessibilityHidden(true)
            if camera.busy && !camera.recording {
                VStack(spacing: 10) {
                    ProgressView().tint(turquoise)
                    Text("Developing…").font(.system(size: 12, weight: .medium))
                }.padding(20).background(navy.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if savedPulse, let latestThumbnail {
                VStack(spacing: 6) {
                    Image(uiImage: latestThumbnail).resizable().scaledToFill()
                        .frame(width: 100, height: 118).clipped()
                    Label("In your roll", systemImage: "checkmark").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(navy)
                }.padding(7).padding(.bottom, 3).background(Color(red: 0.95, green: 0.95, blue: 0.9))
                    .rotationEffect(.degrees(reduceMotion ? 0 : -5)).padding(22)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .scale(scale: 0.75, anchor: .bottomLeading).combined(with: .opacity),
                        removal: .offset(x: -30, y: 110).combined(with: .scale(scale: 0.5, anchor: .bottomLeading)).combined(with: .opacity)))
                    .allowsHitTesting(false)
            }
        }
        .gesture(DragGesture(minimumDistance: 35).onEnded { value in
            guard !locked, abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
            let looks = FilmLook.allCases
            guard let current = looks.firstIndex(of: settings.look) else { return }
            let next = min(max(current + (value.translation.width < 0 ? 1 : -1), 0), looks.count - 1)
            withAnimation(motion) { selectedLook = looks[next].rawValue }
        })
        .animation(motion, value: camera.recording)
    }
    private var filmTray: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(settings.look.rawValue).font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Swipe to change look").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                Spacer(minLength: 4)
                Button { showAdjustments = true } label: {
                    Label("Tune", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .medium))
                        .frame(minHeight: 32)
                }.buttonStyle(CameraPressStyle()).disabled(locked).accessibilityLabel("Adjust look and exposure")
            }.padding(.horizontal, 22)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(FilmLook.allCases) { look in
                            Button {
                                withAnimation(motion) { selectedLook = look.rawValue }
                            } label: {
                                FilmPreview(look: look, image: camera.lookPreviews[look], selected: selectedLook == look.rawValue, namespace: selection)
                            }.buttonStyle(CameraPressStyle()).disabled(locked).id(look.rawValue)
                                .accessibilityLabel("\(look.rawValue), \(look.character)")
                                .accessibilityAddTraits(selectedLook == look.rawValue ? .isSelected : [])
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 3)
                }
                .onChange(of: selectedLook) { _, value in withAnimation(motion) { proxy.scrollTo(value, anchor: .center) } }
                .onAppear { proxy.scrollTo(selectedLook, anchor: .center) }
            }
        }.frame(height: 122)
    }
    private var modeSelector: some View {
        HStack(spacing: 30) {
            ForEach(["PHOTO", "PAIR", "VIDEO"], id: \.self) { item in
                Button {
                    withAnimation(motion) { mode = item }; flash = false; camera.torch(false)
                } label: {
                    VStack(spacing: 6) {
                        Text(item).font(.system(size: 12, weight: .bold)).tracking(1.5)
                            .foregroundStyle(mode == item ? .white : .white.opacity(0.45))
                        ZStack {
                            Capsule().fill(.clear).frame(width: 18, height: 3)
                            if mode == item { Capsule().fill(turquoise).frame(width: 18, height: 3).matchedGeometryEffect(id: "mode", in: selection) }
                        }
                    }.frame(minWidth: 60, minHeight: 36)
                }.buttonStyle(CameraPressStyle()).disabled(locked || camera.firstHalfFrame != nil).accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }.frame(height: 36)
    }
    private var captureBar: some View {
        HStack {
            Button { showGallery = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.16)).frame(width: 47, height: 51)
                        .rotationEffect(.degrees(-7)).offset(x: -3, y: -2)
                    ZStack {
                        RoundedRectangle(cornerRadius: 7).fill(navy)
                        if let latestThumbnail { Image(uiImage: latestThumbnail).resizable().scaledToFill() }
                        else { Image(systemName: "square.stack").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)) }
                    }.frame(width: 48, height: 54).clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.6), lineWidth: 1.5))
                        .rotationEffect(.degrees(savedPulse && !reduceMotion ? -5 : 0))
                        .scaleEffect(savedPulse && !reduceMotion ? 1.1 : 1)
                }.frame(width: 64, height: 64)
                    .overlay(alignment: .bottom) {
                        Text("ROLL").font(.system(size: 8, weight: .medium)).tracking(1.1).offset(y: 11)
                    }.padding(.bottom, 12)
            }.buttonStyle(CameraPressStyle()).accessibilityLabel("Your roll, \(rollCount) captures").disabled(locked || camera.firstHalfFrame != nil)
            Spacer()
            Button { shutter() } label: {
                ShutterFace(video: mode == "VIDEO", recording: camera.recording, start: camera.recordingStarted)
            }.buttonStyle(CameraPressStyle(pressedScale: 0.93))
                .disabled((!camera.ready || camera.busy) && !camera.recording || countdown > 0)
                .accessibilityLabel(camera.recording ? "Stop recording" : mode == "VIDEO" ? "Record video" : mode == "PAIR" ? (camera.firstHalfFrame == nil ? "Take first frame" : "Take second frame") : "Take photo")
            Spacer()
            if camera.firstHalfFrame != nil {
                Button { Task { await camera.cancelPair() } } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "xmark.circle").font(.system(size: 22, weight: .light))
                        Text("CANCEL").font(.system(size: 8, weight: .medium)).tracking(1.1)
                    }.frame(width: 64, height: 76)
                }.buttonStyle(CameraPressStyle()).disabled(locked).accessibilityLabel("Cancel half-frame pair")
            } else {
                PhotosPicker(selection: $imported, matching: .images) {
                    VStack(spacing: 7) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 22, weight: .light))
                        Text("IMPORT").font(.system(size: 8, weight: .medium)).tracking(1.1)
                    }.foregroundStyle(.white.opacity(0.75)).frame(width: 64, height: 76)
                }.buttonStyle(CameraPressStyle()).disabled(locked).accessibilityLabel("Import a photo")
            }
        }.padding(.horizontal, 30).frame(height: 80)
    }
    @MainActor private func refreshRoll() async {
        await camera.refreshRoll()
        guard !Task.isCancelled else { return }
        withAnimation(motion) { savedPulse = camera.latest != nil }
        if savedPulse {
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(motion) { savedPulse = false }
        }
    }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View { VStack(alignment: .leading) { Text(title).font(.subheadline); Slider(value: value, in: range) } }
    private func sync() { camera.update(settings: settings, preserve: keepOriginal, export: exportPhotos) }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
    private func shutter() {
        if camera.recording { flash = false }
        camera.shutter(video: mode == "VIDEO", flash: flash, delay: timerDelay, pair: mode == "PAIR")
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
