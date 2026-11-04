import SwiftUI
import PhotosUI
import CoreImage

// MARK: - Retusche-Werkzeuge

enum RetouchMode: String, CaseIterable, Identifiable {
    case heal, clone, smooth, blur, sharpen, lighten, darken, saturate, desaturate
    var id: String { rawValue }

    var title: String {
        switch self {
        case .heal: return "Heilen"
        case .clone: return "Klonen"
        case .smooth: return "Glätten"
        case .blur: return "Weichzeichnen"
        case .sharpen: return "Schärfen"
        case .lighten: return "Aufhellen"
        case .darken: return "Abdunkeln"
        case .saturate: return "Sättigen"
        case .desaturate: return "Entsättigen"
        }
    }

    var icon: String {
        switch self {
        case .heal: return "bandage"
        case .clone: return "square.on.square"
        case .smooth: return "face.smiling"
        case .blur: return "drop"
        case .sharpen: return "triangle"
        case .lighten: return "sun.max"
        case .darken: return "moon"
        case .saturate: return "paintpalette"
        case .desaturate: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - Modell

@MainActor
final class EditorModel: ObservableObject {
    @Published var display: UIImage?
    @Published var adjust = Adjust()
    @Published var look: LookFilter = .none
    @Published var lookAmount = 1.0
    @Published var thumbs: [LookFilter: UIImage] = [:]
    @Published var canUndo = false
    @Published var hasAlpha = false
    @Published var message: String?

    @Published var mode: RetouchMode = .heal
    @Published var brushSize = 0.06
    @Published var hardness = 0.5
    @Published var opacity = 1.0
    @Published var cloneSource: CGPoint?
    @Published var pickingSource = false
    var cloneOffset: CGPoint?

    private(set) var base: CIImage?
    private var original: CIImage?
    private var undoStack: [CIImage] = []
    private var thumbsDirty = true
    private var showingOriginal = false

    var imageSize: CGSize { base?.extent.size ?? .zero }
    var baseUIImage: UIImage? {
        guard let b = base, let cg = sharedCI.createCGImage(b, from: b.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: Laden / Rendern

    func load(_ image: UIImage) {
        guard let cg = image.cgImage else { return }
        let c = CIImage(cgImage: cg)
        base = c
        original = c
        undoStack = []
        canUndo = false
        adjust = Adjust()
        look = .none
        hasAlpha = false
        cloneSource = nil
        cloneOffset = nil
        thumbsDirty = true
        render()
    }

    func render() {
        guard let b = base else { return }
        let src: CIImage = showingOriginal ? (original ?? b) : process(b)
        if let cg = sharedCI.createCGImage(src, from: src.extent) { display = UIImage(cgImage: cg) }
    }

    private func process(_ i: CIImage) -> CIImage {
        processImage(i, adjust: adjust, look: look, lookAmount: lookAmount)
    }

    func setOriginal(_ on: Bool) { showingOriginal = on; render() }
    func setAdjust(_ kp: WritableKeyPath<Adjust, Double>, _ v: Double) { adjust[keyPath: kp] = v; render() }
    func setLook(_ l: LookFilter) { look = l; render() }
    func setLookAmount(_ v: Double) { lookAmount = v; render() }
    func resetAdjustments() { adjust = Adjust(); look = .none; lookAmount = 1; render() }

    func ensureThumbs() {
        guard thumbsDirty, let b = base else { return }
        let s = 140 / max(b.extent.width, b.extent.height)
        let small = b.transformed(by: CGAffineTransform(scaleX: s, y: s))
        var out: [LookFilter: UIImage] = [:]
        for l in LookFilter.allCases {
            let r = l.apply(small).cropped(to: small.extent)
            if let cg = sharedCI.createCGImage(r, from: small.extent) { out[l] = UIImage(cgImage: cg) }
        }
        thumbs = out
        thumbsDirty = false
    }

    // MARK: Rückgängig / Festschreiben

    private func pushUndo() {
        if let b = base {
            undoStack.append(b)
            if undoStack.count > 12 { undoStack.removeFirst() }
            canUndo = true
        }
    }

    private func normalize(_ i: CIImage) -> CIImage {
        let e = i.extent
        return i.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
    }

    private func bake(_ img: CIImage) {
        let n = normalize(img)
        if let cg = sharedCI.createCGImage(n, from: n.extent) { base = CIImage(cgImage: cg) } else { base = n }
        thumbsDirty = true
        render()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        base = last
        canUndo = !undoStack.isEmpty
        thumbsDirty = true
        render()
    }

    // MARK: Geometrie

    func rotate() { guard let b = base else { return }; pushUndo(); bake(b.oriented(.right)) }
    func flipH() { guard let b = base else { return }; pushUndo(); bake(b.oriented(.upMirrored)) }
    func flipV() { guard let b = base else { return }; pushUndo(); bake(b.oriented(.downMirrored)) }

    func crop(ratio: CGFloat) {
        guard let b = base else { return }
        let e = b.extent
        var w = e.width
        var h = e.height
        if e.width / e.height > ratio { w = h * ratio } else { h = w / ratio }
        let r = CGRect(x: e.minX + (e.width - w) / 2, y: e.minY + (e.height - h) / 2, width: w, height: h).integral
        pushUndo()
        bake(b.cropped(to: r))
    }

    // MARK: Auto

    func autoEnhance() {
        guard let b = base else { return }
        pushUndo()
        var img = b
        for f in b.autoAdjustmentFilters() {
            f.setValue(img, forKey: kCIInputImageKey)
            img = f.outputImage ?? img
        }
        bake(img.cropped(to: b.extent))
    }

    func redEye() {
        guard let b = base else { return }
        let filters = b.autoAdjustmentFilters(options: [.enhance: false, .redEye: true])
        if filters.isEmpty { message = "Keine roten Augen gefunden"; return }
        pushUndo()
        var img = b
        for f in filters {
            f.setValue(img, forKey: kCIInputImageKey)
            img = f.outputImage ?? img
        }
        bake(img.cropped(to: b.extent))
        message = "Rote Augen korrigiert"
    }

    // MARK: Ausschnitt (Smartcut-Ergebnis übernehmen)

    func applyCutout(_ image: UIImage) {
        guard let cg = image.cgImage else { return }
        pushUndo()
        base = CIImage(cgImage: cg)
        hasAlpha = true
        thumbsDirty = true
        render()
    }

    // MARK: Retusche

    private func makeMask(_ pts: [CGPoint], radius: CGFloat, size: CGSize) -> CIImage? {
        guard let first = pts.first else { return nil }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            let c = rc.cgContext
            c.setStrokeColor(UIColor.white.cgColor)
            c.setFillColor(UIColor.white.cgColor)
            c.setLineWidth(radius * 2)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            c.fillEllipse(in: CGRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2))
            if pts.count > 1 {
                c.move(to: first)
                for p in pts.dropFirst() { c.addLine(to: p) }
                c.strokePath()
            }
        }
        guard var m = CIImage(image: img) else { return nil }
        let soft = (1 - hardness) * Double(radius) * 0.5
        if soft > 0.5 {
            let e = m.extent
            m = m.clampedToExtent().applyingGaussianBlur(sigma: soft).cropped(to: e)
        }
        return m
    }

    func applyStroke(_ pts: [CGPoint]) {
        guard let b = base, let start = pts.first else { return }
        let e = b.extent
        let radius = CGFloat(brushSize) * min(e.width, e.height)
        guard let mask = makeMask(pts, radius: radius, size: e.size) else { return }
        let r = Double(radius)

        let effect: CIImage
        switch mode {
        case .heal:
            // Umgebung "diffundiert" in die bemalte Stelle (Fleckenentferner)
            let holed = b.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: mask])
            let sigma = max(4, r * 0.7)
            let fill = ci("CIGaussianBlur", holed, ["inputRadius": sigma]).cropped(to: e)
            let fallback = blurred(b, sigma * 2)
            effect = fill.composited(over: fallback)
        case .clone:
            guard let src = cloneSource else { return }
            if cloneOffset == nil { cloneOffset = CGPoint(x: start.x - src.x, y: start.y - src.y) }
            let off = cloneOffset ?? .zero
            effect = b.transformed(by: CGAffineTransform(translationX: off.x, y: -off.y))
                .clampedToExtent().cropped(to: e)
        case .smooth:
            effect = mix(b, blurred(b, max(3, r * 0.2)), 0.85)
        case .blur:
            effect = blurred(b, max(4, r * 0.35))
        case .sharpen:
            effect = ci("CISharpenLuminance", b, ["inputSharpness": 1.6, "inputRadius": 2.0])
        case .lighten:
            effect = ci("CIExposureAdjust", b, ["inputEV": 0.6])
        case .darken:
            effect = ci("CIExposureAdjust", b, ["inputEV": -0.6])
        case .saturate:
            effect = ci("CIColorControls", b, ["inputSaturation": 1.7])
        case .desaturate:
            effect = ci("CIColorControls", b, ["inputSaturation": 0.0])
        }

        var blendMask = mask
        if opacity < 1 {
            blendMask = mask.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))])
        }
        pushUndo()
        let out = effect.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: b,
            kCIInputMaskImageKey: blendMask
        ]).cropped(to: e)
        bake(out)
    }

    // MARK: Speichern

    func finalImage() -> UIImage? {
        guard let b = base else { return nil }
        let p = process(b)
        guard let cg = sharedCI.createCGImage(p, from: p.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    func save(done: @escaping (Bool) -> Void) {
        guard let img = finalImage() else { done(false); return }
        PhotoSaver.save(img, png: hasAlpha, completion: done)
    }
}

// MARK: - Bildschirm

enum EditorTab: String, CaseIterable {
    case looks, adjust, fix, crop, cutout

    var title: String {
        switch self {
        case .looks: return "Looks"
        case .adjust: return "Änderungen"
        case .fix: return "Korrigieren"
        case .crop: return "Zuschneiden"
        case .cutout: return "Ausschnitt"
        }
    }

    var icon: String {
        switch self {
        case .looks: return "circle.hexagongrid"
        case .adjust: return "slider.horizontal.3"
        case .fix: return "bandage"
        case .crop: return "crop"
        case .cutout: return "scissors"
        }
    }
}

struct EditorScreen: View {
    var startImage: UIImage?
    var onFinish: ((UIImage) -> Void)?

    @StateObject private var m = EditorModel()
    @State private var pick: PhotosPickerItem?
    @State private var tab: EditorTab
    @State private var showCutout = false
    @Environment(\.dismiss) private var dismiss

    init(startImage: UIImage? = nil, onFinish: ((UIImage) -> Void)? = nil, startTab: EditorTab = .adjust) {
        self.startImage = startImage
        self.onFinish = onFinish
        _tab = State(initialValue: startTab)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if m.display == nil {
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 56)).foregroundStyle(.secondary)
                    PhotosPicker(selection: $pick, matching: .images) {
                        Text("Foto auswählen").bold()
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(Color.blue, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    canvas
                    panel
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(Color(white: 0.08))
                    tabBar
                }
            }
            if let msg = m.message {
                Text(msg).font(.footnote).padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
            }
        }
        .navigationTitle("Bearb. & Retusche")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if onFinish != nil {
                    Button("Abbrechen") { dismiss() }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if m.display != nil {
                    Image(systemName: "eye")
                        .onLongPressGesture(minimumDuration: 0, maximumDistance: 60, pressing: { m.setOriginal($0) }, perform: {})
                    Button { m.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!m.canUndo)
                    PhotosPicker(selection: $pick, matching: .images) { Image(systemName: "photo.badge.plus") }
                    if let finish = onFinish {
                        Button("Fertig") {
                            if let img = m.finalImage() { finish(img) }
                            dismiss()
                        }.bold()
                    } else {
                        Button {
                            m.save { ok in m.message = ok ? "In Fotos gesichert" : "Speichern nicht erlaubt" }
                        } label: { Image(systemName: "square.and.arrow.down") }
                    }
                }
            }
        }
        .onChange(of: pick) { _, item in load(item) }
        .task {
            if let s = startImage, m.display == nil { m.load(s) }
        }
        .task(id: m.message) {
            if m.message != nil {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                m.message = nil
            }
        }
        .fullScreenCover(isPresented: $showCutout) {
            if let img = m.baseUIImage {
                SmartcutView(image: img, startAll: true) { result in
                    if let r = result { m.applyCutout(r) }
                    showCutout = false
                }
            }
        }
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let d = try? await item.loadTransferable(type: Data.self),
               let img = preparedImage(from: d, maxSide: 2048) {
                m.load(img)
            }
            pick = nil
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            if let img = m.display {
                let r = fitRect(img.size, in: geo.size)
                ZStack {
                    Image(uiImage: img).resizable()
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                    if tab == .fix {
                        RetouchLayer(m: m, rect: r, imgSize: img.size)
                    }
                }
            }
        }
    }

    @ViewBuilder private var panel: some View {
        switch tab {
        case .looks: LooksPanel(m: m)
        case .adjust: AdjustPanel(m: m)
        case .fix: RetouchPanel(m: m)
        case .crop: CropPanel(m: m)
        case .cutout: CutoutPanel(m: m, open: { showCutout = true })
        }
    }

    private var tabBar: some View {
        HStack {
            ForEach(EditorTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.title3)
                        Text(t.title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(tab == t ? Color.blue : Color.white)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color.black)
    }
}

// MARK: - Retusche-Ebene (Malen auf dem Bild)

struct RetouchLayer: View {
    @ObservedObject var m: EditorModel
    let rect: CGRect
    let imgSize: CGSize
    @State private var pts: [CGPoint] = []

    private var scale: CGFloat { rect.width / max(imgSize.width, 1) }
    private var diameter: CGFloat { CGFloat(m.brushSize) * min(imgSize.width, imgSize.height) * scale * 2 }

    private func toImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max((p.x - rect.minX) / scale, 0), imgSize.width),
                y: min(max((p.y - rect.minY) / scale, 0), imgSize.height))
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + p.x * scale, y: rect.minY + p.y * scale)
    }

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            Path { path in
                guard let f = pts.first else { return }
                path.move(to: f)
                for q in pts.dropFirst() { path.addLine(to: q) }
                if pts.count == 1 { path.addLine(to: f) }
            }
            .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: diameter, lineCap: .round, lineJoin: .round))
            .allowsHitTesting(false)
            if let s = m.cloneSource {
                Image(systemName: "scope").font(.title).foregroundStyle(.yellow)
                    .position(toView(s)).allowsHitTesting(false)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if let l = pts.last, hypot(l.x - v.location.x, l.y - v.location.y) < 2 { return }
                    pts.append(v.location)
                }
                .onEnded { _ in finish() }
        )
    }

    private func finish() {
        let ip = pts.map(toImage)
        pts = []
        guard let first = ip.first else { return }
        if m.pickingSource || (m.mode == .clone && m.cloneSource == nil) {
            m.cloneSource = first
            m.cloneOffset = nil
            m.pickingSource = false
        } else {
            m.applyStroke(ip)
        }
    }
}

// MARK: - Panels

struct AdjustPanel: View {
    @ObservedObject var m: EditorModel
    @State private var sel = adjSpecs[0].id

    private var spec: AdjSpec { adjSpecs.first { $0.id == sel } ?? adjSpecs[0] }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(adjSpecs) { s in
                        Button { sel = s.id } label: {
                            VStack(spacing: 4) {
                                Image(systemName: s.icon).font(.title3)
                                Text(s.name).font(.caption2)
                            }
                            .frame(width: 78, height: 56)
                            .foregroundStyle(sel == s.id ? Color.white : Color.gray)
                            .background(sel == s.id ? Color.blue.opacity(0.6) : Color(white: 0.15),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                Slider(value: Binding(get: { m.adjust[keyPath: spec.keyPath] },
                                      set: { m.setAdjust(spec.keyPath, $0) }),
                       in: spec.range)
                Text("\(Int((m.adjust[keyPath: spec.keyPath] * 100).rounded()))")
                    .monospacedDigit().frame(width: 44)
            }
            .padding(.horizontal)
            Button("Alles zurücksetzen") { m.resetAdjustments() }.font(.footnote)
        }
        .padding(.top, 12)
    }
}

struct LooksPanel: View {
    @ObservedObject var m: EditorModel

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(LookFilter.allCases) { l in
                        Button { m.setLook(l) } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    if let t = m.thumbs[l] {
                                        Image(uiImage: t).resizable().scaledToFill()
                                    } else {
                                        Color.gray.opacity(0.3)
                                    }
                                }
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(m.look == l ? Color.blue : Color.clear, lineWidth: 3))
                                Text(l.title).font(.caption2)
                                    .foregroundStyle(m.look == l ? Color.blue : Color.white)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                Text("Stärke").font(.footnote)
                Slider(value: Binding(get: { m.lookAmount }, set: { m.setLookAmount($0) }), in: 0...1)
            }
            .padding(.horizontal)
        }
        .padding(.top, 12)
        .onAppear { m.ensureThumbs() }
    }
}

struct CropPanel: View {
    @ObservedObject var m: EditorModel
    private let ratios: [(String, CGFloat)] = [
        ("1:1", 1), ("4:5", 0.8), ("5:4", 1.25), ("3:4", 0.75), ("4:3", 4.0 / 3.0),
        ("2:3", 2.0 / 3.0), ("3:2", 1.5), ("9:16", 9.0 / 16.0), ("16:9", 16.0 / 9.0)
    ]

    var body: some View {
        VStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ratios, id: \.0) { r in
                        Button { m.crop(ratio: r.1) } label: {
                            Text(r.0).font(.footnote.bold())
                                .frame(width: 60, height: 40)
                                .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal)
            }
            HStack(spacing: 24) {
                actionButton("Drehen", "rotate.right") { m.rotate() }
                actionButton("Horizontal", "arrow.left.and.right.righttriangle.left.righttriangle.right") { m.flipH() }
                actionButton("Vertikal", "arrow.up.and.down.righttriangle.up.righttriangle.down") { m.flipV() }
            }
            Text("Zuschnitt erfolgt mittig. Mit Rückgängig wieder zurücknehmen.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.top, 14)
    }

    private func actionButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.caption2)
            }
            .frame(width: 80, height: 56)
            .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
        }
    }
}

struct RetouchPanel: View {
    @ObservedObject var m: EditorModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RetouchMode.allCases) { r in
                            Button { m.mode = r } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: r.icon).font(.title3)
                                    Text(r.title).font(.caption2)
                                }
                                .frame(width: 84, height: 52)
                                .foregroundStyle(m.mode == r ? Color.white : Color.gray)
                                .background(m.mode == r ? Color.blue.opacity(0.6) : Color(white: 0.15),
                                            in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                if m.mode == .clone {
                    HStack {
                        Text(m.cloneSource == nil || m.pickingSource ? "Tippe auf die Quelle, dann male."
                                                                       : "Quelle gesetzt – male auf die Zielstelle.")
                            .font(.caption)
                        Spacer()
                        Button("Quelle neu") { m.pickingSource = true }.font(.caption.bold())
                    }
                    .padding(.horizontal)
                }
                slider("Größe", $m.brushSize, 0.01...0.2)
                slider("Härte", $m.hardness, 0...1)
                slider("Deckkraft", $m.opacity, 0.05...1)
                Button("Rote Augen automatisch korrigieren") { m.redEye() }.font(.footnote)
            }
            .padding(.top, 10)
        }
    }

    private func slider(_ t: String, _ v: Binding<Double>, _ r: ClosedRange<Double>) -> some View {
        HStack {
            Text(t).font(.footnote).frame(width: 70, alignment: .leading)
            Slider(value: v, in: r)
        }
        .padding(.horizontal)
    }
}

struct CutoutPanel: View {
    @ObservedObject var m: EditorModel
    let open: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: open) {
                Label("Smartcut – Motiv freistellen", systemImage: "wand.and.stars")
                    .bold().frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            Button { m.autoEnhance() } label: {
                Label("Auto-Optimierung", systemImage: "sparkles")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            Text("Smartcut erkennt Objekte automatisch. Danach kannst du Objekte antippen oder mit dem Pinsel korrigieren.")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal)
        }
        .padding(.top, 14)
    }
}
