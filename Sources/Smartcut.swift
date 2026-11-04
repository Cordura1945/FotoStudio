import SwiftUI
import Vision
import CoreImage

struct VisionBundle: @unchecked Sendable {
    let obs: VNInstanceMaskObservation
    let handler: VNImageRequestHandler
}

/// Smartcut-Engine: erkennt Objekte (Apple Vision), erlaubt Objekte per Tippen
/// hinzuzufügen/zu entfernen, Pinsel-Korrekturen und Kanten-Verfeinerung.
@MainActor
final class CutoutEngine: ObservableObject {
    let source: UIImage
    private let srcImage: CIImage
    private let extent: CGRect

    @Published var preview: UIImage?
    @Published var ready = false
    @Published var detected = 0
    @Published var canUndo = false
    @Published var feather: Double = 0 { didSet { renderPreview() } }
    @Published var smooth: Double = 0 { didSet { renderPreview() } }
    @Published var shift: Double = 0 { didSet { renderPreview() } }
    @Published var showRed = false { didSet { renderPreview() } }

    private var bundle: VisionBundle?
    private var instanceMasks: [Int: CIImage] = [:]
    private var selected = IndexSet()
    private var strokes: [(CIImage, Bool)] = []
    private var baseMask: CIImage
    private var undoStack: [(IndexSet, [(CIImage, Bool)], CIImage)] = []
    private var finalMask: CIImage

    var imageSize: CGSize { extent.size }

    init(image: UIImage) {
        let s = CIImage(cgImage: image.cgImage!)
        let black = CIImage(color: CIColor.black).cropped(to: s.extent)
        source = image
        srcImage = s
        extent = s.extent
        baseMask = black
        finalMask = black
    }

    // MARK: Analyse

    func analyze(selectAll: Bool) async {
        guard let cg = source.cgImage else { ready = true; return }
        let result: VisionBundle? = await Task.detached(priority: .userInitiated) { () -> VisionBundle? in
            let req = VNGenerateForegroundInstanceMaskRequest()
            let h = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try h.perform([req]) } catch { return nil }
            guard let o = req.results?.first else { return nil }
            return VisionBundle(obs: o, handler: h)
        }.value
        if let b = result {
            bundle = b
            detected = b.obs.allInstances.count
            selected = selectAll ? b.obs.allInstances : IndexSet()
        }
        ready = true
        rebuild()
    }

    // MARK: Masken

    private func gray(_ m: CIImage) -> CIImage {
        ci("CIColorMatrix", m, [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
    }

    private func instanceMask(_ i: Int) -> CIImage? {
        if let m = instanceMasks[i] { return m }
        guard let b = bundle,
              let buf = try? b.obs.generateScaledMaskForImage(forInstances: IndexSet(integer: i), from: b.handler)
        else { return nil }
        var m = CIImage(cvPixelBuffer: buf)
        let sx = extent.width / m.extent.width
        let sy = extent.height / m.extent.height
        if abs(sx - 1) > 0.001 || abs(sy - 1) > 0.001 {
            m = m.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        m = gray(m).cropped(to: extent)
        instanceMasks[i] = m
        return m
    }

    private func bake(_ m: CIImage) -> CIImage {
        if let cg = sharedCI.createCGImage(m, from: extent) { return CIImage(cgImage: cg) }
        return m
    }

    private func applyOne(_ stroke: CIImage, add: Bool, to m: CIImage) -> CIImage {
        if add {
            return stroke.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: m])
        } else {
            let inv = stroke.applyingFilter("CIColorInvert")
            return inv.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: m])
        }
    }

    private func rebuild() {
        var m = CIImage(color: CIColor.black).cropped(to: extent)
        for i in selected {
            if let im = instanceMask(i) {
                m = im.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: m])
            }
        }
        for (s, add) in strokes { m = applyOne(s, add: add, to: m) }
        baseMask = bake(m.cropped(to: extent))
        renderPreview()
    }

    private func pushUndo() {
        undoStack.append((selected, strokes, baseMask))
        if undoStack.count > 20 { undoStack.removeFirst() }
        canUndo = true
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        selected = last.0
        strokes = last.1
        baseMask = last.2
        canUndo = !undoStack.isEmpty
        renderPreview()
    }

    // MARK: Smartcut (Tippen auf Objekt)

    private func label(at p: CGPoint) -> Int? {
        guard let b = bundle else { return nil }
        let buf = b.obs.instanceMask
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let w = CVPixelBufferGetWidth(buf)
        let h = CVPixelBufferGetHeight(buf)
        let bpr = CVPixelBufferGetBytesPerRow(buf)
        let cx = Int(p.x / extent.width * CGFloat(w))
        let cy = Int(p.y / extent.height * CGFloat(h))
        func val(_ x: Int, _ y: Int) -> Int {
            guard x >= 0, y >= 0, x < w, y < h else { return 0 }
            return Int(base.load(fromByteOffset: y * bpr + x, as: UInt8.self))
        }
        for r in [0, 3, 8, 16, 32] {
            for dy in stride(from: -r, through: r, by: max(1, r / 2)) {
                for dx in stride(from: -r, through: r, by: max(1, r / 2)) {
                    let v = val(cx + dx, cy + dy)
                    if v > 0 { return v }
                }
            }
        }
        return nil
    }

    /// Objekt unter dem Finger hinzufügen/entfernen. Gibt false zurück, wenn dort kein Objekt erkannt wurde.
    @discardableResult
    func smartTap(at p: CGPoint, add: Bool) -> Bool {
        guard let l = label(at: p) else { return false }
        pushUndo()
        if add { selected.insert(l) } else { selected.remove(l) }
        rebuild()
        return true
    }

    // MARK: Zauberstab (Fallback, wenn Vision nichts erkennt)

    /// Wählt den zusammenhängenden Bereich ähnlicher Farbe unter dem Finger.
    @discardableResult
    func wandTap(at p: CGPoint, add: Bool, tolerance: Double) -> Bool {
        guard let cg = source.cgImage else { return false }
        let sc = min(1, 420 / max(extent.width, extent.height))
        let w = Int((extent.width * sc).rounded())
        let h = Int((extent.height * sc).rounded())
        guard w > 2, h > 2 else { return false }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = px.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return false }
        let sx = min(max(Int(p.x * sc), 0), w - 1)
        let sy = min(max(Int(p.y * sc), 0), h - 1)
        // Startfarbe: Mittel über 3x3
        var acc = [Int](repeating: 0, count: 3)
        var n = 0
        for dy in -1...1 { for dx in -1...1 {
            let x = sx + dx, y = sy + dy
            guard x >= 0, y >= 0, x < w, y < h else { continue }
            let o = (y * w + x) * 4
            acc[0] += Int(px[o]); acc[1] += Int(px[o + 1]); acc[2] += Int(px[o + 2]); n += 1
        } }
        let seed = acc.map { $0 / max(n, 1) }
        let tol = Int(tolerance)
        var mask = [UInt8](repeating: 0, count: w * h)
        var stack = [(sx, sy)]
        mask[sy * w + sx] = 255
        var count = 0
        while let (x, y) = stack.popLast() {
            count += 1
            for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] {
                guard nx >= 0, ny >= 0, nx < w, ny < h, mask[ny * w + nx] == 0 else { continue }
                let o = (ny * w + nx) * 4
                let d = max(abs(Int(px[o]) - seed[0]), abs(Int(px[o + 1]) - seed[1]), abs(Int(px[o + 2]) - seed[2]))
                if d <= tol {
                    mask[ny * w + nx] = 255
                    stack.append((nx, ny))
                }
            }
        }
        guard count > 3 else { return false }
        let data = Data(mask)
        guard let prov = CGDataProvider(data: data as CFData),
              let mcg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return false }
        var m = CIImage(cgImage: mcg)
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(w), y: extent.height / CGFloat(h)))
        m = blurred(m.clampedToExtent(), 1.5).cropped(to: extent)
        pushUndo()
        strokes.append((m, add))
        baseMask = bake(applyOne(m, add: add, to: baseMask).cropped(to: extent))
        renderPreview()
        return true
    }

    // MARK: Pinsel

    func paint(points: [CGPoint], radius: CGFloat, hardness: Double, add: Bool) {
        guard let first = points.first else { return }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let size = extent.size
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            let c = rc.cgContext
            c.setFillColor(UIColor.black.cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            c.setStrokeColor(UIColor.white.cgColor)
            c.setFillColor(UIColor.white.cgColor)
            c.setLineWidth(radius * 2)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            c.fillEllipse(in: CGRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2))
            if points.count > 1 {
                c.move(to: first)
                for p in points.dropFirst() { c.addLine(to: p) }
                c.strokePath()
            }
        }
        guard var s = CIImage(image: img) else { return }
        let soft = (1 - hardness) * Double(radius) * 0.5
        if soft > 0.5 { s = blurred(s, soft * 2) }
        pushUndo()
        strokes.append((s, add))
        baseMask = bake(applyOne(s, add: add, to: baseMask).cropped(to: extent))
        renderPreview()
    }

    // MARK: Ausgabe

    private func refined() -> CIImage {
        var m = baseMask
        if shift != 0 {
            let name = shift > 0 ? "CIMorphologyMaximum" : "CIMorphologyMinimum"
            m = ci(name, m.clampedToExtent(), ["inputRadius": abs(shift)]).cropped(to: extent)
        }
        if smooth > 0 {
            m = blurred(m, smooth * 5)
            let k = CGFloat(1 + smooth * 6)
            m = ci("CIColorMatrix", m, [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0.5 - 0.5 * k, y: 0.5 - 0.5 * k, z: 0.5 - 0.5 * k, w: 0)
            ])
        }
        if feather > 0 { m = blurred(m, feather) }
        return m.cropped(to: extent)
    }

    private func applyAlpha(_ img: CIImage, _ mask: CIImage) -> CIImage {
        let a = mask.applyingFilter("CIMaskToAlpha")
        return img.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: a])
    }

    func renderPreview() {
        guard ready else { return }
        finalMask = refined()
        let out: CIImage
        if showRed {
            let a = finalMask.applyingFilter("CIColorInvert").applyingFilter("CIMaskToAlpha")
            let red = CIImage(color: CIColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.55)).cropped(to: extent)
            let tint = red.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: a])
            out = tint.composited(over: srcImage)
        } else {
            let cut = applyAlpha(srcImage, finalMask)
            var bg = srcImage
            if let f = CIFilter(name: "CICheckerboardGenerator") {
                f.setValue(CIVector(x: 0, y: 0), forKey: "inputCenter")
                f.setValue(CIColor(red: 0.30, green: 0.30, blue: 0.32), forKey: "inputColor0")
                f.setValue(CIColor(red: 0.20, green: 0.20, blue: 0.22), forKey: "inputColor1")
                f.setValue(max(extent.width, extent.height) / 40, forKey: "inputWidth")
                f.setValue(1.0, forKey: "inputSharpness")
                if let o = f.outputImage { bg = o.cropped(to: extent) }
            }
            // Das Originalbild bleibt als blasser Hintergrund sichtbar
            bg = mix(bg, srcImage, 0.3)
            out = cut.composited(over: bg)
        }
        if let cg = sharedCI.createCGImage(out, from: extent) { preview = UIImage(cgImage: cg) }
    }

    func result() -> UIImage? {
        let cut = applyAlpha(srcImage, refined())
        guard let cg = sharedCI.createCGImage(cut, from: extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Oberfläche

struct SmartcutView: View {
    @StateObject private var e: CutoutEngine
    private let startAll: Bool
    private let onDone: (UIImage?) -> Void

    @State private var tab = 0          // 0 Hinzufügen, 1 Entfernen, 2 Verfeinern
    @State private var tool = 0         // 0 Smartcut, 1 Pinsel
    @State private var tol = 40.0
    @State private var brush = 0.06
    @State private var hardness = 0.6
    @State private var pts: [CGPoint] = []
    @State private var note: String?

    init(image: UIImage, startAll: Bool, onDone: @escaping (UIImage?) -> Void) {
        _e = StateObject(wrappedValue: CutoutEngine(image: image))
        self.startAll = startAll
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            canvas
            panel
        }
        .background(Color.black.ignoresSafeArea())
        .task { await e.analyze(selectAll: startAll) }
        .task(id: note) {
            if note != nil {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                note = nil
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("Abbrechen") { onDone(nil) }
            Spacer()
            Text("Ausschnitt").bold()
            Spacer()
            Button { e.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!e.canUndo)
                .padding(.trailing, 12)
            Button("Fertig") { onDone(e.result()) }.bold()
        }
        .padding()
    }

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                if let img = e.preview {
                    let r = fitRect(img.size, in: geo.size)
                    let s = r.width / max(img.size.width, 1)
                    ZStack {
                        Image(uiImage: img).resizable()
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                        if tab != 2 && tool == 1 {
                            Path { p in
                                guard let f = pts.first else { return }
                                p.move(to: f)
                                for q in pts.dropFirst() { p.addLine(to: q) }
                                if pts.count == 1 { p.addLine(to: f) }
                            }
                            .stroke(tab == 0 ? Color.green.opacity(0.5) : Color.red.opacity(0.5),
                                    style: StrokeStyle(lineWidth: CGFloat(brush) * min(img.size.width, img.size.height) * s * 2,
                                                       lineCap: .round, lineJoin: .round))
                            .allowsHitTesting(false)
                        }
                        Color.clear.contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { v in
                                        guard tab != 2, tool == 1 else { return }
                                        if let l = pts.last, hypot(l.x - v.location.x, l.y - v.location.y) < 2 { return }
                                        pts.append(v.location)
                                    }
                                    .onEnded { v in finish(v.location, rect: r, scale: s, imgSize: img.size) }
                            )
                    }
                } else {
                    ProgressView("Analysiere Motiv …").tint(.white)
                }
                if let n = note {
                    Text(n).font(.footnote).padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
                }
            }
        }
    }

    private func toImage(_ p: CGPoint, rect: CGRect, scale: CGFloat, size: CGSize) -> CGPoint {
        CGPoint(x: min(max((p.x - rect.minX) / scale, 0), size.width),
                y: min(max((p.y - rect.minY) / scale, 0), size.height))
    }

    private func finish(_ loc: CGPoint, rect: CGRect, scale: CGFloat, imgSize: CGSize) {
        guard tab != 2 else { return }
        if tool == 0 {
            let p = toImage(loc, rect: rect, scale: scale, size: imgSize)
            if e.detected == 0 || !e.smartTap(at: p, add: tab == 0) {
                if !e.wandTap(at: p, add: tab == 0, tolerance: tol) {
                    note = "Dort wurde nichts erkannt – nutze den Pinsel"
                }
            }
        } else {
            let ip = pts.map { toImage($0, rect: rect, scale: scale, size: imgSize) }
            pts = []
            if !ip.isEmpty {
                let radius = CGFloat(brush) * min(imgSize.width, imgSize.height)
                e.paint(points: ip, radius: radius, hardness: hardness, add: tab == 0)
            }
        }
    }

    private var panel: some View {
        VStack(spacing: 12) {
            Picker("", selection: $tab) {
                Text("Hinzufügen").tag(0)
                Text("Entfernen").tag(1)
                Text("Verfeinern").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if tab == 2 {
                refine
            } else {
                HStack(spacing: 20) {
                    toolButton("Smartcut", "wand.and.stars", 0)
                    toolButton("Pinsel", "paintbrush.pointed", 1)
                }
                if tool == 1 {
                    HStack { Text("Größe").frame(width: 70, alignment: .leading); Slider(value: $brush, in: 0.01...0.2) }
                        .padding(.horizontal)
                    HStack { Text("Härte").frame(width: 70, alignment: .leading); Slider(value: $hardness, in: 0...1) }
                        .padding(.horizontal)
                } else {
                    HStack { Text("Toleranz").frame(width: 70, alignment: .leading); Slider(value: $tol, in: 5...120) }
                        .padding(.horizontal)
                    Text((tab == 0 ? "Tippe auf ein Objekt oder einen Bereich, um ihn zum Ausschnitt hinzuzufügen."
                                   : "Tippe auf ein Objekt oder einen Bereich, um ihn zu entfernen.")
                         + (e.detected == 0 ? " Kein Motiv erkannt – es wird nach Farbe ausgewählt." : ""))
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                }
            }
        }
        .font(.footnote)
        .padding(.vertical, 10)
        .frame(minHeight: 190)
    }

    private func toolButton(_ title: String, _ icon: String, _ t: Int) -> some View {
        Button { tool = t } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                Text(title)
            }
            .frame(width: 90, height: 64)
            .foregroundStyle(tool == t ? Color.white : Color.gray)
            .background(tool == t ? Color.blue.opacity(0.6) : Color(white: 0.15), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var refine: some View {
        VStack(spacing: 8) {
            HStack { Text("Kante weich").frame(width: 100, alignment: .leading); Slider(value: $e.feather, in: 0...20) }
            HStack { Text("Glätten").frame(width: 100, alignment: .leading); Slider(value: $e.smooth, in: 0...1) }
            HStack { Text("Kante verschieben").frame(width: 100, alignment: .leading); Slider(value: $e.shift, in: -8...8) }
            Toggle("Entfernten Bereich rot zeigen", isOn: $e.showRed).padding(.top, 2)
        }
        .padding(.horizontal)
    }
}
