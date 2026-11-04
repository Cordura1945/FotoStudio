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

enum FixTool: String, CaseIterable, Identifiable {
    case remove, patch, clone, object, more
    var id: String { rawValue }
    var title: String {
        switch self {
        case .remove: return "Entfernen"
        case .patch: return "Ausbessern"
        case .clone: return "Klonen"
        case .object: return "Objekte entfernen"
        case .more: return "Mehr"
        }
    }
}

func boxCenter(_ pts: [CGPoint]) -> CGPoint {
    guard let f = pts.first else { return .zero }
    var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
    for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
    return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
}

func boxRect(_ pts: [CGPoint]) -> CGRect {
    guard let f = pts.first else { return .zero }
    var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
    for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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
    @Published var canRedo = false
    @Published var fixTool: FixTool = .remove
    @Published var sizePreview = false
    @Published var patchPts: [CGPoint] = []
    @Published var patchOffset: CGPoint = .zero
    @Published var patchScale = 1.0
    @Published var patchOpacity = 1.0
    @Published var patchFeather = 0.3
    @Published var patchBlend = true
    private var liveBase: CIImage?
    private var redoStack: [CIImage] = []
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
        redoStack = []
        canUndo = false
        canRedo = false
        liveBase = nil
        patchPts = []
        adjust = Adjust()
        look = .none
        hasAlpha = false
        cloneSource = nil
        cloneOffset = nil
        thumbsDirty = true
        render()
    }

    func render() {
        guard let b = liveBase ?? base else { return }
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
            redoStack = []
            canRedo = false
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
        if !patchPts.isEmpty { cancelPatch(); return }
        guard let last = undoStack.popLast() else { return }
        if let b = base { redoStack.append(b) }
        base = last
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        thumbsDirty = true
        render()
    }

    func redo() {
        if !patchPts.isEmpty { cancelPatch() }
        guard let next = redoStack.popLast() else { return }
        if let b = base { undoStack.append(b) }
        base = next
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
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
        let hd = fixTool == .remove ? 0.7 : hardness
        let soft = (1 - hd) * Double(radius) * 0.5
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
            effect = healFill(b, mask: mask, radius: r)
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
        let op = fixTool == .remove ? 1.0 : opacity
        if op < 1 {
            blendMask = mask.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(op))])
        }
        pushUndo()
        let out = effect.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: b,
            kCIInputMaskImageKey: blendMask
        ]).cropped(to: e)
        bake(out)
    }

    // Mehrstufige Füllung: Umgebung "diffundiert" in die Lücke
    private func healFill(_ b: CIImage, mask: CIImage, radius r: Double) -> CIImage {
        let e = b.extent
        let holed = b.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        let s1 = max(3, r * 0.35)
        var fill = ci("CIGaussianBlur", holed, ["inputRadius": s1]).cropped(to: e)
        for k in [3.0, 9.0] {
            let l = ci("CIGaussianBlur", holed, ["inputRadius": s1 * k]).cropped(to: e)
            fill = fill.composited(over: l)
        }
        let fallback = blurred(b, s1 * 12)
        return fill.composited(over: fallback)
    }

    private func polygonMask(_ pts: [CGPoint], size: CGSize, grow: CGFloat) -> CIImage? {
        guard pts.count > 2 else { return nil }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            let c = rc.cgContext
            c.setFillColor(UIColor.white.cgColor)
            c.setStrokeColor(UIColor.white.cgColor)
            c.setLineWidth(max(1, grow * 2))
            c.setLineJoin(.round)
            c.move(to: pts[0])
            for p in pts.dropFirst() { c.addLine(to: p) }
            c.closePath()
            c.drawPath(using: .fillStroke)
        }
        return CIImage(image: img)
    }

    /// Objekte entfernen: Umkreisen, Fläche wird aus der Umgebung gefüllt.
    func removeObject(_ pts: [CGPoint]) {
        guard let b = base, pts.count > 2 else { return }
        let e = b.extent
        let box = boxRect(pts)
        let side = Double(max(box.width, box.height))
        guard var mask = polygonMask(pts, size: e.size, grow: max(3, CGFloat(side) * 0.04)) else { return }
        let sm = mask.extent
        mask = mask.clampedToExtent().applyingGaussianBlur(sigma: max(1.5, side * 0.02)).cropped(to: sm)
        let fill = healFill(b, mask: mask, radius: max(8, side * 0.5))
        pushUndo()
        bake(fill.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: b, kCIInputMaskImageKey: mask
        ]).cropped(to: e))
    }

    // MARK: Ausbessern (Blase verschieben / skalieren)

    func selectFix(_ t: FixTool) {
        if fixTool == .patch && t != .patch { cancelPatch() }
        fixTool = t
        switch t {
        case .remove: mode = .heal
        case .clone: mode = .clone
        case .more: if mode == .heal || mode == .clone { mode = .smooth }
        default: break
        }
    }

    func patchBegin(_ pts: [CGPoint]) {
        patchPts = pts
        patchOffset = .zero
        patchScale = 1
        updatePatch()
    }

    func cancelPatch() {
        patchPts = []
        patchOffset = .zero
        patchScale = 1
        liveBase = nil
        render()
    }

    func commitPatch() {
        guard let l = liveBase else { cancelPatch(); return }
        pushUndo()
        liveBase = nil
        patchPts = []
        patchOffset = .zero
        patchScale = 1
        bake(l)
    }

    func updatePatch() {
        guard let b = base, patchPts.count > 2 else { liveBase = nil; render(); return }
        liveBase = patchComposite(b)
        render()
    }

    private func average(_ img: CIImage, _ r: CGRect) -> [Double]? {
        let rr = r.intersection(img.extent)
        guard !rr.isNull, rr.width > 1, rr.height > 1 else { return nil }
        let out = ci("CIAreaAverage", img.cropped(to: rr), ["inputExtent": CIVector(cgRect: rr)])
        var px = [UInt8](repeating: 0, count: 4)
        sharedCI.render(out, toBitmap: &px, rowBytes: 4,
                        bounds: CGRect(x: out.extent.minX, y: out.extent.minY, width: 1, height: 1),
                        format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return px.prefix(3).map { Double($0) / 255 }
    }

    private func patchComposite(_ b: CIImage) -> CIImage {
        let e = b.extent
        let H = e.height
        let c0 = boxCenter(patchPts)
        let c0f = CGPoint(x: c0.x, y: H - c0.y)
        let c1f = CGPoint(x: c0f.x + patchOffset.x, y: c0f.y - patchOffset.y)
        let s = CGFloat(max(0.1, patchScale))
        let t = CGAffineTransform.identity
            .translatedBy(x: c0f.x, y: c0f.y)
            .scaledBy(x: 1 / s, y: 1 / s)
            .translatedBy(x: -c1f.x, y: -c1f.y)
        var src = b.clampedToExtent().transformed(by: t).cropped(to: e)

        guard var mask = polygonMask(patchPts, size: e.size, grow: 0) else { return b }
        let box = boxRect(patchPts)
        let side = Double(max(box.width, box.height))
        let sigma = patchFeather * side * 0.12
        if sigma > 0.5 {
            let me = mask.extent
            mask = mask.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: me)
        }
        if patchOpacity < 1 {
            mask = mask.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(patchOpacity))])
        }
        if patchBlend {
            let rf = CGRect(x: box.minX, y: H - box.maxY, width: box.width, height: box.height)
            if let a = average(src, rf), let d = average(b, rf) {
                src = src.applyingFilter("CIColorMatrix", parameters: [
                    "inputBiasVector": CIVector(x: CGFloat(d[0] - a[0]), y: CGFloat(d[1] - a[1]), z: CGFloat(d[2] - a[2]), w: 0)
                ]).cropped(to: e)
            }
        }
        return src.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: b, kCIInputMaskImageKey: mask
        ]).cropped(to: e)
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
                        .frame(height: tab == .fix ? 240 : 200)
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
                        if m.fixTool == .patch {
                            PatchLayer(m: m, rect: r, imgSize: img.size)
                        } else {
                            RetouchLayer(m: m, rect: r, imgSize: img.size)
                        }
                        if m.sizePreview {
                            Circle().stroke(Color.white, lineWidth: 2)
                                .background(Circle().fill(Color.white.opacity(0.25)))
                                .frame(width: CGFloat(m.brushSize) * min(img.size.width, img.size.height) * (r.width / max(img.size.width, 1)) * 2,
                                       height: CGFloat(m.brushSize) * min(img.size.width, img.size.height) * (r.width / max(img.size.width, 1)) * 2)
                                .position(x: r.midX, y: r.midY)
                                .allowsHitTesting(false)
                        }
                    }
                    HStack(spacing: 8) {
                        floatButton("arrow.uturn.backward", enabled: m.canUndo || !m.patchPts.isEmpty) { m.undo() }
                        floatButton("arrow.uturn.forward", enabled: m.canRedo) { m.redo() }
                        Spacer()
                        Image(systemName: "rectangle.split.2x1")
                            .font(.title3).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                            .onLongPressGesture(minimumDuration: 0, maximumDistance: 80, pressing: { m.setOriginal($0) }, perform: {})
                    }
                    .padding(10)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }

    private func floatButton(_ icon: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3)
                .frame(width: 44, height: 44)
                .foregroundStyle(enabled ? Color.white : Color.gray)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        }
        .disabled(!enabled)
    }

    @ViewBuilder private var panel: some View {
        switch tab {
        case .looks: LooksPanel(m: m)
        case .adjust: AdjustPanel(m: m)
        case .fix: FixPanel(m: m)
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
    private var overlayColor: Color {
        (m.fixTool == .remove || m.fixTool == .object) ? Color.red.opacity(0.5) : Color.white.opacity(0.45)
    }
    private var lineW: CGFloat { m.fixTool == .object ? 4 : diameter }
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
            .stroke(overlayColor, style: StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round))
            .allowsHitTesting(false)
            if m.fixTool == .object, pts.count > 2 {
                Path { path in
                    path.move(to: pts[0])
                    for q in pts.dropFirst() { path.addLine(to: q) }
                    path.closeSubpath()
                }
                .fill(Color.red.opacity(0.3)).allowsHitTesting(false)
            }
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
        } else if m.fixTool == .object {
            m.removeObject(ip)
        } else {
            m.applyStroke(ip)
        }
    }
}

// MARK: - Ausbessern-Ebene (Blase zeichnen, verschieben, skalieren)

struct PatchLayer: View {
    @ObservedObject var m: EditorModel
    let rect: CGRect
    let imgSize: CGSize
    @State private var draw: [CGPoint] = []
    @State private var dragMode = 0
    @State private var startOffset: CGPoint = .zero
    @State private var pinchBase: Double?

    private var scale: CGFloat { rect.width / max(imgSize.width, 1) }

    private func toImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max((p.x - rect.minX) / scale, 0), imgSize.width),
                y: min(max((p.y - rect.minY) / scale, 0), imgSize.height))
    }

    private func shapeView() -> [CGPoint] {
        let c0 = boxCenter(m.patchPts)
        let s = CGFloat(m.patchScale)
        return m.patchPts.map { p in
            let q = CGPoint(x: c0.x + m.patchOffset.x + (p.x - c0.x) * s,
                            y: c0.y + m.patchOffset.y + (p.y - c0.y) * s)
            return CGPoint(x: rect.minX + q.x * scale, y: rect.minY + q.y * scale)
        }
    }

    private func closedPath(_ pts: [CGPoint]) -> Path {
        Path { p in
            guard let f = pts.first else { return }
            p.move(to: f)
            for q in pts.dropFirst() { p.addLine(to: q) }
            p.closeSubpath()
        }
    }

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            if m.patchPts.count > 2 {
                let sv = shapeView()
                closedPath(sv).fill(Color.blue.opacity(0.12)).allowsHitTesting(false)
                closedPath(sv).stroke(Color.blue, lineWidth: 2.5).allowsHitTesting(false)
            }
            Path { p in
                guard let f = draw.first else { return }
                p.move(to: f)
                for q in draw.dropFirst() { p.addLine(to: q) }
            }
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .allowsHitTesting(false)
            if m.patchPts.isEmpty && draw.isEmpty {
                Text("Umkreise die Stelle, die du ausbessern möchtest")
                    .font(.caption).padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 10)
                    .allowsHitTesting(false)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if dragMode == 0 {
                        if m.patchPts.count > 2, closedPath(shapeView()).contains(v.startLocation) {
                            dragMode = 2
                            startOffset = m.patchOffset
                        } else {
                            dragMode = 1
                            if !m.patchPts.isEmpty { m.cancelPatch() }
                        }
                    }
                    if dragMode == 2 {
                        m.patchOffset = CGPoint(x: startOffset.x + v.translation.width / scale,
                                                y: startOffset.y + v.translation.height / scale)
                        m.updatePatch()
                    } else {
                        if let l = draw.last, hypot(l.x - v.location.x, l.y - v.location.y) < 2 { return }
                        draw.append(v.location)
                    }
                }
                .onEnded { _ in
                    if dragMode == 1 {
                        if draw.count > 8 { m.patchBegin(draw.map(toImage)) }
                        draw = []
                    }
                    dragMode = 0
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { v in
                    guard m.patchPts.count > 2 else { return }
                    if pinchBase == nil { pinchBase = m.patchScale }
                    m.patchScale = min(3, max(0.3, (pinchBase ?? 1) * Double(v.magnification)))
                    m.updatePatch()
                }
                .onEnded { _ in pinchBase = nil }
        )
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

enum FixOpt { case size, hardness, opacity, feather }

struct FixPanel: View {
    @ObservedObject var m: EditorModel
    @State private var opt: FixOpt = .size

    private var brushTool: Bool { m.fixTool == .remove || m.fixTool == .clone || m.fixTool == .more }

    private var sliderBinding: Binding<Double> {
        switch (m.fixTool, opt) {
        case (.patch, .size):
            return Binding(get: { m.patchScale }, set: { m.patchScale = $0; m.updatePatch() })
        case (.patch, .opacity):
            return Binding(get: { m.patchOpacity }, set: { m.patchOpacity = $0; m.updatePatch() })
        case (.patch, _):
            return Binding(get: { m.patchFeather }, set: { m.patchFeather = $0; m.updatePatch() })
        case (_, .hardness): return $m.hardness
        case (_, .opacity): return $m.opacity
        default: return $m.brushSize
        }
    }

    private var range: ClosedRange<Double> {
        switch (m.fixTool, opt) {
        case (.patch, .size): return 0.3...3
        case (.patch, .opacity): return 0.05...1
        case (.patch, _): return 0...1
        case (_, .hardness): return 0...1
        case (_, .opacity): return 0.05...1
        default: return 0.01...0.2
        }
    }

    private var valueText: String {
        let v = sliderBinding.wrappedValue
        let r = range
        return "\(Int(((v - r.lowerBound) / (r.upperBound - r.lowerBound) * 100).rounded()))"
    }

    private var showSlider: Bool { m.fixTool != .object }

    var body: some View {
        VStack(spacing: 8) {
            if showSlider {
                HStack {
                    Slider(value: sliderBinding, in: range, onEditingChanged: { editing in
                        m.sizePreview = editing && opt == .size && brushTool
                    })
                    Text(valueText).monospacedDigit().font(.footnote).frame(width: 36)
                }
                .padding(.horizontal)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(FixTool.allCases) { t in
                        Button { m.selectFix(t); opt = .size } label: {
                            Text(t.title).font(.subheadline)
                                .foregroundStyle(m.fixTool == t ? Color.blue : Color.white)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 28)
            options
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    @ViewBuilder private var options: some View {
        switch m.fixTool {
        case .remove:
            VStack(spacing: 10) {
                optionRow([(.size, "Größe", "circle.dashed")])
                hint("Male über das Objekt, das du entfernen möchtest.")
            }
        case .object:
            VStack(spacing: 10) {
                Image(systemName: "lasso.badge.sparkles").font(.title)
                hint("Umkreise das Objekt, es wird aus der Umgebung ersetzt.")
            }
        case .clone:
            VStack(spacing: 8) {
                optionRow([(.size, "Größe", "circle.dashed"), (.hardness, "Härte", "circle.lefthalf.filled"), (.opacity, "Deckkraft", "checkerboard.rectangle")])
                HStack {
                    Text(m.cloneSource == nil || m.pickingSource ? "Tippe auf die Quelle, dann male." : "Quelle gesetzt – male auf die Zielstelle.")
                        .font(.caption)
                    Spacer()
                    Button("Quelle neu") { m.pickingSource = true }.font(.caption.bold())
                }.padding(.horizontal)
            }
        case .patch:
            VStack(spacing: 8) {
                HStack(spacing: 14) {
                    optionRow([(.size, "Größe", "arrow.up.left.and.arrow.down.right"), (.opacity, "Deckkraft", "checkerboard.rectangle"), (.feather, "Verwischen", "circle.fill")])
                    Divider().frame(height: 50)
                    VStack(spacing: 4) {
                        Toggle("", isOn: Binding(get: { m.patchBlend }, set: { m.patchBlend = $0; m.updatePatch() }))
                            .labelsHidden()
                        Text("Mischen").font(.caption2).foregroundStyle(.blue)
                    }
                }
                if m.patchPts.count > 2 {
                    HStack(spacing: 20) {
                        Button { m.cancelPatch() } label: { Label("Verwerfen", systemImage: "xmark") }
                        Button { m.commitPatch() } label: { Label("Anwenden", systemImage: "checkmark").bold() }
                    }
                    .font(.footnote)
                } else {
                    hint("Blase ziehen = Quelle wählen, zwei Finger = größer/kleiner.")
                }
            }
        case .more:
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RetouchMode.allCases.filter { $0 != .heal && $0 != .clone }) { r in
                            Button { m.mode = r } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: r.icon).font(.title3)
                                    Text(r.title).font(.caption2)
                                }
                                .frame(width: 84, height: 50)
                                .foregroundStyle(m.mode == r ? Color.white : Color.gray)
                                .background(m.mode == r ? Color.blue.opacity(0.6) : Color(white: 0.15),
                                            in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }.padding(.horizontal)
                }
                Button("Rote Augen automatisch korrigieren") { m.redEye() }.font(.footnote)
            }
        }
    }

    private func hint(_ t: String) -> some View {
        Text(t).font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).padding(.horizontal)
    }

    private func optionRow(_ items: [(FixOpt, String, String)]) -> some View {
        HStack(spacing: 10) {
            ForEach(items, id: \.1) { it in
                Button { opt = it.0 } label: {
                    VStack(spacing: 4) {
                        Image(systemName: it.2).font(.title3)
                            .frame(width: 56, height: 46)
                            .background(opt == it.0 ? Color.blue : Color(white: 0.18), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                        Text(it.1).font(.caption2)
                            .foregroundStyle(opt == it.0 ? Color.blue : Color.white)
                    }
                }
            }
        }
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
