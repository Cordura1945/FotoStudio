import SwiftUI
import PhotosUI
import CoreImage

// MARK: - Grundtypen

enum BlendChoice: String, CaseIterable, Identifiable {
    case normal, multiply, screen, overlay, softLight, hardLight, darken, lighten, colorDodge, colorBurn, difference
    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .multiply: return "Multiplizieren"
        case .screen: return "Negativ multipl."
        case .overlay: return "Ineinanderkopieren"
        case .softLight: return "Weiches Licht"
        case .hardLight: return "Hartes Licht"
        case .darken: return "Abdunkeln"
        case .lighten: return "Aufhellen"
        case .colorDodge: return "Abwedeln"
        case .colorBurn: return "Nachbelichten"
        case .difference: return "Differenz"
        }
    }

    var mode: BlendMode {
        switch self {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .darken: return .darken
        case .lighten: return .lighten
        case .colorDodge: return .colorDodge
        case .colorBurn: return .colorBurn
        case .difference: return .difference
        }
    }
}

struct AspectPreset: Identifiable {
    let id = UUID()
    let name: String
    let w: CGFloat
    let h: CGFloat
    var ratio: CGFloat { w / h }
}

struct AspectCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let colors: [Color]
    let presets: [AspectPreset]
}

let aspectCategories: [AspectCategory] = [
    AspectCategory(name: "Einfach", icon: "square", colors: [.teal, .blue], presets: [
        AspectPreset(name: "Quadrat 1:1", w: 1, h: 1),
        AspectPreset(name: "4:5", w: 4, h: 5),
        AspectPreset(name: "5:4", w: 5, h: 4),
        AspectPreset(name: "3:4", w: 3, h: 4),
        AspectPreset(name: "4:3", w: 4, h: 3),
        AspectPreset(name: "2:3", w: 2, h: 3),
        AspectPreset(name: "3:2", w: 3, h: 2),
        AspectPreset(name: "9:16", w: 9, h: 16),
        AspectPreset(name: "16:9", w: 16, h: 9)
    ]),
    AspectCategory(name: "Soziale Medien", icon: "heart.text.square", colors: [.pink, .red], presets: [
        AspectPreset(name: "Instagram Post", w: 1, h: 1),
        AspectPreset(name: "Instagram Hochformat", w: 4, h: 5),
        AspectPreset(name: "Story / Reel / TikTok", w: 9, h: 16),
        AspectPreset(name: "Facebook Beitrag", w: 1200, h: 630),
        AspectPreset(name: "Facebook Titelbild", w: 820, h: 312),
        AspectPreset(name: "X / Twitter Beitrag", w: 16, h: 9),
        AspectPreset(name: "YouTube Thumbnail", w: 1280, h: 720),
        AspectPreset(name: "Pinterest Pin", w: 2, h: 3),
        AspectPreset(name: "LinkedIn Banner", w: 1584, h: 396)
    ]),
    AspectCategory(name: "Drucken", icon: "printer", colors: [.orange, .yellow], presets: [
        AspectPreset(name: "A4 hoch", w: 210, h: 297),
        AspectPreset(name: "A4 quer", w: 297, h: 210),
        AspectPreset(name: "A5 hoch", w: 148, h: 210),
        AspectPreset(name: "Foto 10 × 15 cm", w: 10, h: 15),
        AspectPreset(name: "Foto 13 × 18 cm", w: 13, h: 18),
        AspectPreset(name: "Foto 15 × 20 cm", w: 15, h: 20),
        AspectPreset(name: "Poster 50 × 70 cm", w: 50, h: 70),
        AspectPreset(name: "Postkarte A6 quer", w: 148, h: 105),
        AspectPreset(name: "Visitenkarte 85 × 55", w: 85, h: 55)
    ]),
    AspectCategory(name: "Digitale Anzeigen", icon: "rectangle.on.rectangle", colors: [.purple, .indigo], presets: [
        AspectPreset(name: "Leaderboard 728 × 90", w: 728, h: 90),
        AspectPreset(name: "Medium Rectangle 300 × 250", w: 300, h: 250),
        AspectPreset(name: "Large Rectangle 336 × 280", w: 336, h: 280),
        AspectPreset(name: "Skyscraper 160 × 600", w: 160, h: 600),
        AspectPreset(name: "Half Page 300 × 600", w: 300, h: 600),
        AspectPreset(name: "Mobile Banner 320 × 50", w: 320, h: 50),
        AspectPreset(name: "Billboard 970 × 250", w: 970, h: 250)
    ])
]

func gridCells(_ cols: Int, _ rows: Int) -> [CGRect] {
    var out: [CGRect] = []
    for r in 0..<rows {
        for c in 0..<cols {
            out.append(CGRect(x: CGFloat(c) / CGFloat(cols), y: CGFloat(r) / CGFloat(rows),
                              width: 1 / CGFloat(cols), height: 1 / CGFloat(rows)))
        }
    }
    return out
}

enum CollageTemplate: String, CaseIterable, Identifiable {
    case free, twoSide, twoStack, threeCols, threeRows, threeLeft, threeTop, grid4, grid6, grid9
    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Frei"
        case .twoSide: return "2 nebeneinander"
        case .twoStack: return "2 übereinander"
        case .threeCols: return "3 Spalten"
        case .threeRows: return "3 Zeilen"
        case .threeLeft: return "1 groß + 2"
        case .threeTop: return "Oben groß"
        case .grid4: return "Raster 2×2"
        case .grid6: return "Raster 2×3"
        case .grid9: return "Raster 3×3"
        }
    }

    var cells: [CGRect] {
        switch self {
        case .free: return []
        case .twoSide: return gridCells(2, 1)
        case .twoStack: return gridCells(1, 2)
        case .threeCols: return gridCells(3, 1)
        case .threeRows: return gridCells(1, 3)
        case .threeLeft:
            return [CGRect(x: 0, y: 0, width: 0.6, height: 1),
                    CGRect(x: 0.6, y: 0, width: 0.4, height: 0.5),
                    CGRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5)]
        case .threeTop:
            return [CGRect(x: 0, y: 0, width: 1, height: 0.6),
                    CGRect(x: 0, y: 0.6, width: 0.5, height: 0.4),
                    CGRect(x: 0.5, y: 0.6, width: 0.5, height: 0.4)]
        case .grid4: return gridCells(2, 2)
        case .grid6: return gridCells(2, 3)
        case .grid9: return gridCells(3, 3)
        }
    }
}

// MARK: - Hintergrund

struct CanvasBackground: Equatable {
    enum Kind: Equatable { case color, gradient(Int), pattern(Int) }
    var kind: Kind = .color
    var color: Color = .white
    var color2: Color = Color(white: 0.82)
    var transparent = false
}

let gradientPresets: [[Color]] = [
    [Color(red: 1.0, green: 0.55, blue: 0.3), Color(red: 0.95, green: 0.2, blue: 0.5)],
    [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.5, green: 0.2, blue: 0.9)],
    [Color(red: 0.1, green: 0.8, blue: 0.6), Color(red: 0.1, green: 0.4, blue: 0.9)],
    [Color(red: 1.0, green: 0.85, blue: 0.3), Color(red: 1.0, green: 0.4, blue: 0.2)],
    [Color(red: 0.95, green: 0.6, blue: 0.8), Color(red: 0.6, green: 0.7, blue: 1.0)],
    [Color(white: 0.95), Color(white: 0.6)],
    [Color(white: 0.25), Color.black],
    [Color(red: 0.05, green: 0.1, blue: 0.3), Color(red: 0.4, green: 0.1, blue: 0.5)],
    [Color(red: 0.7, green: 1.0, blue: 0.6), Color(red: 0.1, green: 0.6, blue: 0.5)],
    [Color(red: 1.0, green: 0.9, blue: 0.9), Color(red: 1.0, green: 0.7, blue: 0.5)]
]

let patternNames = ["Streifen", "Punkte", "Karo", "Rauten", "Gitter", "Zickzack", "Wellen", "Dreiecke"]

struct PatternView: View {
    let index: Int
    let c1: Color
    let c2: Color

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c1))
            let cell = max(size.width, 1) / 12
            let cols = Int(size.width / cell) + 2
            let rows = Int(size.height / cell) + 2
            switch index {
            case 0:
                for i in stride(from: 0, to: cols, by: 2) {
                    ctx.fill(Path(CGRect(x: CGFloat(i) * cell, y: 0, width: cell, height: size.height)), with: .color(c2))
                }
            case 1:
                for r in 0..<rows {
                    for c in 0..<cols {
                        let x = (CGFloat(c) + (r % 2 == 0 ? 0.5 : 1.0)) * cell
                        let y = (CGFloat(r) + 0.5) * cell
                        ctx.fill(Path(ellipseIn: CGRect(x: x - cell * 0.25, y: y - cell * 0.25, width: cell * 0.5, height: cell * 0.5)),
                                 with: .color(c2))
                    }
                }
            case 2:
                for r in 0..<rows {
                    for c in 0..<cols where (r + c) % 2 == 0 {
                        ctx.fill(Path(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)), with: .color(c2))
                    }
                }
            case 3:
                for r in 0..<rows {
                    for c in 0..<cols {
                        let cx = (CGFloat(c) + 0.5) * cell
                        let cy = (CGFloat(r) + 0.5) * cell
                        var p = Path()
                        p.move(to: CGPoint(x: cx, y: cy - cell * 0.45))
                        p.addLine(to: CGPoint(x: cx + cell * 0.45, y: cy))
                        p.addLine(to: CGPoint(x: cx, y: cy + cell * 0.45))
                        p.addLine(to: CGPoint(x: cx - cell * 0.45, y: cy))
                        p.closeSubpath()
                        ctx.fill(p, with: .color(c2))
                    }
                }
            case 4:
                var p = Path()
                for c in 0..<cols { p.addRect(CGRect(x: CGFloat(c) * cell, y: 0, width: cell * 0.08, height: size.height)) }
                for r in 0..<rows { p.addRect(CGRect(x: 0, y: CGFloat(r) * cell, width: size.width, height: cell * 0.08)) }
                ctx.fill(p, with: .color(c2))
            case 5:
                for r in 0..<rows {
                    var p = Path()
                    let y = (CGFloat(r) + 0.5) * cell
                    p.move(to: CGPoint(x: 0, y: y))
                    for c in 0..<(cols * 2) {
                        p.addLine(to: CGPoint(x: CGFloat(c + 1) * cell / 2, y: y + (c % 2 == 0 ? -cell * 0.25 : cell * 0.25)))
                    }
                    ctx.stroke(p, with: .color(c2), lineWidth: cell * 0.12)
                }
            case 6:
                for r in 0..<rows {
                    var p = Path()
                    let y = (CGFloat(r) + 0.5) * cell
                    p.move(to: CGPoint(x: 0, y: y))
                    var x: CGFloat = 0
                    while x < size.width + cell {
                        p.addQuadCurve(to: CGPoint(x: x + cell, y: y), control: CGPoint(x: x + cell / 2, y: y + (Int(x / cell) % 2 == 0 ? -cell * 0.5 : cell * 0.5)))
                        x += cell
                    }
                    ctx.stroke(p, with: .color(c2), lineWidth: cell * 0.12)
                }
            default:
                for r in 0..<rows {
                    for c in 0..<cols {
                        var p = Path()
                        let x = CGFloat(c) * cell
                        let y = CGFloat(r) * cell
                        if (r + c) % 2 == 0 {
                            p.move(to: CGPoint(x: x, y: y + cell))
                            p.addLine(to: CGPoint(x: x + cell, y: y + cell))
                            p.addLine(to: CGPoint(x: x + cell / 2, y: y))
                        } else {
                            p.move(to: CGPoint(x: x, y: y))
                            p.addLine(to: CGPoint(x: x + cell, y: y))
                            p.addLine(to: CGPoint(x: x + cell / 2, y: y + cell))
                        }
                        p.closeSubpath()
                        ctx.fill(p, with: .color(c2))
                    }
                }
            }
        }
    }
}

struct BackgroundView: View {
    let bg: CanvasBackground

    var body: some View {
        if bg.transparent {
            Color.clear
        } else {
            switch bg.kind {
            case .color:
                bg.color
            case .gradient(let i):
                LinearGradient(colors: gradientPresets[i % gradientPresets.count], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .pattern(let i):
                PatternView(index: i, c1: bg.color, c2: bg.color2)
            }
        }
    }
}

// MARK: - Ebenen

struct TextSpec: Equatable {
    var text = "Text"
    var fontIndex = 0
    var size: CGFloat = 120
    var color: Color = .white
    var bold = true
    var outline = false
}

func renderText(_ s: TextSpec) -> UIImage {
    var font = UIFont.systemFont(ofSize: s.size, weight: s.bold ? .heavy : .regular)
    var design: UIFontDescriptor.SystemDesign?
    switch s.fontIndex {
    case 1: design = .rounded
    case 2: design = .serif
    case 3: design = .monospaced
    default: design = nil
    }
    if let d = design, let desc = font.fontDescriptor.withDesign(d) { font = UIFont(descriptor: desc, size: s.size) }
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: UIColor(s.color),
        .paragraphStyle: para
    ]
    if s.outline {
        attrs[.strokeColor] = UIColor.black
        attrs[.strokeWidth] = -4.0
    }
    let str = NSAttributedString(string: s.text.isEmpty ? " " : s.text, attributes: attrs)
    let box = str.boundingRect(with: CGSize(width: 1400, height: CGFloat.greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin], context: nil).integral
    let pad: CGFloat = 24
    let size = CGSize(width: max(box.width, 10) + pad * 2, height: max(box.height, 10) + pad * 2)
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    fmt.opaque = false
    return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
        str.draw(with: CGRect(x: pad, y: pad, width: box.width, height: box.height),
                 options: [.usesLineFragmentOrigin], context: nil)
    }
}

func renderEmoji(_ e: String) -> UIImage {
    let size = CGSize(width: 512, height: 512)
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    fmt.opaque = false
    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 400)]
    let str = NSAttributedString(string: e, attributes: attrs)
    let b = str.size()
    return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
        str.draw(at: CGPoint(x: (size.width - b.width) / 2, y: (size.height - b.height) / 2))
    }
}

func renderSymbol(_ name: String, color: UIColor) -> UIImage {
    let cfg = UIImage.SymbolConfiguration(pointSize: 300, weight: .bold)
    let base = UIImage(systemName: name, withConfiguration: cfg) ?? UIImage()
    let tinted = base.withTintColor(color, renderingMode: .alwaysOriginal)
    let size = CGSize(width: tinted.size.width + 40, height: tinted.size.height + 40)
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    fmt.opaque = false
    return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
        tinted.draw(at: CGPoint(x: 20, y: 20))
    }
}

struct CLayer: Identifiable {
    let id = UUID()
    var name: String
    var source: UIImage
    var cut: UIImage?
    var adjust = Adjust()
    var look: LookFilter = .none
    var lookAmount = 1.0
    var rendered: UIImage
    var text: TextSpec?
    var offset: CGSize = .zero      // relativ zur Canvas-Breite
    var scale: CGFloat = 1
    var rotation: Angle = .zero
    var opacity = 1.0
    var blend: BlendChoice = .normal
    var flipH = false
    var visible = true
    var locked = false
    var stretch = CGSize(width: 1, height: 1)
    var quad = [CGPoint](repeating: .zero, count: 4)   // Eckversatz (Anteil der Ebenengröße)
    var shown: UIImage?                                 // verzerrte Darstellung (2x Fläche, mittig)
    var cell: CGRect?

    init(name: String, image: UIImage) {
        self.name = name
        self.source = image
        self.rendered = image
    }
}

// MARK: - Canvas

struct CanvasView: View {
    let layers: [CLayer]
    let bg: CanvasBackground
    let size: CGSize
    let gap: Double
    let corner: Double

    var body: some View {
        ZStack {
            BackgroundView(bg: bg)
            ForEach(layers) { l in
                if l.visible { layerView(l) }
            }
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .clipped()
    }

    @ViewBuilder
    private func layerView(_ l: CLayer) -> some View {
        let W = size.width
        let H = size.height
        let sx = l.flipH ? -l.scale : l.scale
        if let c = l.cell {
            let r = CGRect(x: c.minX * W, y: c.minY * H, width: c.width * W, height: c.height * H)
                .insetBy(dx: CGFloat(gap) * W / 2, dy: CGFloat(gap) * W / 2)
            Image(uiImage: l.rendered).resizable().scaledToFill()
                .frame(width: max(r.width, 1), height: max(r.height, 1))
                .scaleEffect(x: sx, y: l.scale)
                .rotationEffect(l.rotation)
                .offset(x: l.offset.width * W, y: l.offset.height * W)
                .frame(width: max(r.width, 1), height: max(r.height, 1))
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(corner) * W))
                .opacity(l.opacity)
                .blendMode(l.blend.mode)
                .position(x: r.midX, y: r.midY)
        } else {
            let fit = fitSize(l.rendered.size, within: CGSize(width: W * 0.6, height: H * 0.6))
            let p: CGFloat = l.shown == nil ? 1 : 2
            Image(uiImage: l.shown ?? l.rendered).resizable()
                .frame(width: max(fit.width * p * l.stretch.width, 1), height: max(fit.height * p * l.stretch.height, 1))
                .scaleEffect(x: sx, y: l.scale)
                .rotationEffect(l.rotation)
                .offset(x: l.offset.width * W, y: l.offset.height * W)
                .opacity(l.opacity)
                .blendMode(l.blend.mode)
                .position(x: W / 2, y: H / 2)
        }
    }
}

// MARK: - Modell

@MainActor
final class CombineModel: ObservableObject {
    @Published var layers: [CLayer] = [] { didSet { touched() } }
    @Published var selected: UUID?
    @Published var ratio: CGFloat = 1 { didSet { touched() } }
    @Published var aspectName = "Quadrat 1:1" { didSet { touched() } }
    @Published var bg = CanvasBackground() { didSet { touched() } }
    @Published var template: CollageTemplate = .free { didSet { touched() } }
    @Published var gap = 0.01 { didSet { touched() } }
    @Published var corner = 0.0 { didSet { touched() } }
    @Published var canUndo = false
    @Published var canRedo = false

    struct Snap {
        var layers: [CLayer]
        var ratio: CGFloat
        var aspectName: String
        var bg: CanvasBackground
        var template: CollageTemplate
        var gap: Double
        var corner: Double
    }
    private var undoStack: [Snap] = []
    private var redoStack: [Snap] = []
    private var lastStable: Snap?
    private var pendingBefore: Snap?
    private var restoring = false
    private var debounce: Task<Void, Never>?

    private func snap() -> Snap {
        Snap(layers: layers, ratio: ratio, aspectName: aspectName, bg: bg, template: template, gap: gap, corner: corner)
    }

    private func touched() {
        guard !restoring else { return }
        if pendingBefore == nil {
            pendingBefore = lastStable ?? Snap(layers: [], ratio: 1, aspectName: "Quadrat 1:1", bg: CanvasBackground(), template: .free, gap: 0.01, corner: 0)
        }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            self?.flush()
        }
    }

    private func flush() {
        guard let before = pendingBefore else { return }
        pendingBefore = nil
        undoStack.append(before)
        if undoStack.count > 20 { undoStack.removeFirst() }
        redoStack = []
        lastStable = snap()
        canUndo = true
        canRedo = false
    }

    private func restore(_ s: Snap) {
        restoring = true
        layers = s.layers; ratio = s.ratio; aspectName = s.aspectName
        bg = s.bg; template = s.template; gap = s.gap; corner = s.corner
        restoring = false
        lastStable = s
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        if let sel = selected, layer(sel) == nil { selected = layers.last?.id }
    }

    func undo() {
        debounce?.cancel()
        flush()
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snap())
        restore(s)
    }

    func redo() {
        debounce?.cancel()
        flush()
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snap())
        restore(s)
    }

    // Verzerren (Neigen / Verzerrung / Perspektive)
    func warped(_ img: UIImage, quad q: [CGPoint]) -> UIImage? {
        guard let cg = img.cgImage, q.count == 4 else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let c = CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: w / 2, y: h / 2))
        func pt(_ x: CGFloat, _ y: CGFloat, _ i: Int) -> CIVector {
            CIVector(x: x + q[i].x * w, y: y - q[i].y * h)
        }
        guard let f = CIFilter(name: "CIPerspectiveTransform") else { return nil }
        f.setValue(c, forKey: kCIInputImageKey)
        f.setValue(pt(w / 2, 1.5 * h, 0), forKey: "inputTopLeft")
        f.setValue(pt(1.5 * w, 1.5 * h, 1), forKey: "inputTopRight")
        f.setValue(pt(1.5 * w, h / 2, 2), forKey: "inputBottomRight")
        f.setValue(pt(w / 2, h / 2, 3), forKey: "inputBottomLeft")
        guard let out = f.outputImage,
              let r = sharedCI.createCGImage(out, from: CGRect(x: 0, y: 0, width: 2 * w, height: 2 * h)) else { return nil }
        return UIImage(cgImage: r)
    }

    func rewarp(_ id: UUID) {
        guard let l = layer(id) else { return }
        let zero = l.quad.allSatisfy { $0 == .zero }
        let img = zero ? nil : warped(l.rendered, quad: l.quad)
        update(id) { $0.shown = img }
    }

    func toggleLock(_ id: UUID) { update(id) { $0.locked.toggle() } }
    @Published var busy = false
    @Published var message: String?

    var selectedLayer: CLayer? { layer(selected) }

    func layer(_ id: UUID?) -> CLayer? {
        guard let id else { return nil }
        return layers.first { $0.id == id }
    }

    func update(_ id: UUID, _ f: (inout CLayer) -> Void) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        var l = layers[i]
        f(&l)
        layers[i] = l
    }

    func refresh(_ id: UUID) {
        update(id) { l in
            l.rendered = applyLookAndAdjust(l.cut ?? l.source, adjust: l.adjust, look: l.look, amount: l.lookAmount)
        }
        rewarp(id)
    }

    func add(_ imgs: [UIImage], name: String = "Foto") {
        for img in imgs {
            var l = CLayer(name: "\(name) \(layers.count + 1)", image: img)
            if template == .free { l.offset = CGSize(width: CGFloat(layers.count % 5) * 0.03, height: CGFloat(layers.count % 5) * 0.03) }
            layers.append(l)
            selected = l.id
        }
        assignCells(reset: false)
    }

    func addText(_ spec: TextSpec) {
        var l = CLayer(name: "Text", image: renderText(spec))
        l.text = spec
        layers.append(l)
        selected = l.id
    }

    func updateText(_ id: UUID, _ spec: TextSpec) {
        update(id) { l in
            let img = renderText(spec)
            l.text = spec
            l.source = img
            l.cut = nil
            l.rendered = img
            l.quad = [CGPoint](repeating: .zero, count: 4)
            l.shown = nil
        }
    }

    func assignCells(reset: Bool) {
        let cells = template.cells
        var n = 0
        for i in layers.indices {
            if layers[i].text != nil { continue }
            if n < cells.count {
                layers[i].cell = cells[n]
                if reset { layers[i].offset = .zero; layers[i].scale = 1; layers[i].rotation = .zero }
                n += 1
            } else {
                layers[i].cell = nil
            }
        }
    }

    func applyTemplate(_ t: CollageTemplate) {
        template = t
        assignCells(reset: true)
    }

    func remove(_ id: UUID) {
        layers.removeAll { $0.id == id }
        if selected == id { selected = layers.last?.id }
        assignCells(reset: false)
    }

    func duplicate(_ id: UUID) {
        guard let l = layer(id) else { return }
        var c = CLayerCopy.copy(l)
        c.offset = CGSize(width: l.offset.width + 0.04, height: l.offset.height + 0.04)
        c.cell = nil
        if let i = layers.firstIndex(where: { $0.id == id }) { layers.insert(c, at: i + 1) }
        selected = c.id
    }

    func toFront(_ id: UUID) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        let l = layers.remove(at: i)
        layers.append(l)
    }

    func toBack(_ id: UUID) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        let l = layers.remove(at: i)
        layers.insert(l, at: 0)
    }

    func resetTransform(_ id: UUID) {
        update(id) {
            $0.offset = .zero; $0.scale = 1; $0.rotation = .zero; $0.flipH = false
            $0.stretch = CGSize(width: 1, height: 1)
            $0.quad = [CGPoint](repeating: .zero, count: 4)
            $0.shown = nil
        }
    }

    func hit(_ p: CGPoint, canvas cs: CGSize) {
        for l in layers.reversed() where l.visible {
            let rect: CGRect
            if let c = l.cell {
                rect = CGRect(x: c.minX * cs.width, y: c.minY * cs.height, width: c.width * cs.width, height: c.height * cs.height)
            } else {
                let f = fitSize(l.rendered.size, within: CGSize(width: cs.width * 0.6, height: cs.height * 0.6))
                let w = f.width * l.scale * l.stretch.width
                let h = f.height * l.scale * l.stretch.height
                rect = CGRect(x: cs.width / 2 + l.offset.width * cs.width - w / 2,
                              y: cs.height / 2 + l.offset.height * cs.width - h / 2, width: w, height: h)
            }
            if rect.contains(p) { selected = l.id; return }
        }
    }

    // Ausschnitt "Thema": automatisch freistellen
    func autoCutout(_ id: UUID) {
        guard let l = layer(id), !busy else { return }
        busy = true
        let src = l.source
        Task {
            let out = await Cutout.run(src)
            busy = false
            if let out {
                update(id) { $0.cut = out }
                refresh(id)
            } else {
                message = "Kein Motiv erkannt"
            }
        }
    }

    func clearCutout(_ id: UUID) {
        update(id) { $0.cut = nil }
        refresh(id)
    }

    func exportImage() -> UIImage? {
        let longest: CGFloat = 2400
        let w = ratio >= 1 ? longest : longest * ratio
        let h = w / ratio
        let view = CanvasView(layers: layers, bg: bg, size: CGSize(width: w, height: h), gap: gap, corner: corner)
        let r = ImageRenderer(content: view)
        r.scale = 1
        return r.uiImage
    }
}

enum CLayerCopy {
    static func copy(_ l: CLayer) -> CLayer {
        var c = CLayer(name: l.name + " Kopie", image: l.source)
        c.cut = l.cut
        c.adjust = l.adjust
        c.look = l.look
        c.lookAmount = l.lookAmount
        c.rendered = l.rendered
        c.text = l.text
        c.offset = l.offset
        c.scale = l.scale
        c.rotation = l.rotation
        c.opacity = l.opacity
        c.blend = l.blend
        c.flipH = l.flipH
        c.stretch = l.stretch
        c.quad = l.quad
        c.shown = l.shown
        c.locked = l.locked
        return c
    }
}

// MARK: - Bildschirm

enum CTab: String, CaseIterable {
    case aspect, grid, cutout, edit, transform, background, text, sticker

    var title: String {
        switch self {
        case .aspect: return "Seitenverh."
        case .grid: return "Raster"
        case .cutout: return "Ausschnitt"
        case .edit: return "Bearb."
        case .transform: return "Transf."
        case .background: return "Hintergrund"
        case .text: return "Text"
        case .sticker: return "Sticker"
        }
    }

    var icon: String {
        switch self {
        case .aspect: return "rectangle.on.rectangle.angled"
        case .grid: return "square.grid.2x2"
        case .cutout: return "scissors"
        case .edit: return "pencil"
        case .transform: return "arrow.up.left.and.arrow.down.right"
        case .background: return "circle.grid.3x3"
        case .text: return "textformat"
        case .sticker: return "face.smiling"
        }
    }
}

struct CombineScreen: View {
    @StateObject private var m = CombineModel()
    @State private var items: [PhotosPickerItem] = []
    @State private var tab: CTab = .aspect
    @State private var dragStart: CGSize?
    @State private var scaleStart: CGFloat?
    @State private var rotStart: Angle?
    @State private var showLayers = false
    @State private var smartcutStartAll = true
    @State private var showSmartcut = false
    @State private var editorFor: EditorRequest?
    @State private var tmode: TMode = .free

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                canvasArea
                if !m.layers.isEmpty || tab == .aspect || tab == .background || tab == .text {
                    panel
                        .frame(height: 210)
                        .frame(maxWidth: .infinity)
                        .background(Color(white: 0.08))
                }
                tabBar
            }
            if m.busy {
                ProgressView().scaleEffect(1.4).padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            if let msg = m.message {
                Text(msg).font(.footnote).padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
            }
        }
        .navigationTitle("Fotos kombinieren")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                PhotosPicker(selection: $items, maxSelectionCount: 9, matching: .images) {
                    Image(systemName: "plus.circle")
                }
                Button { showLayers = true } label: { Image(systemName: "square.3.layers.3d") }
                Button { save() } label: { Image(systemName: "square.and.arrow.down") }
                    .disabled(m.layers.isEmpty)
            }
        }
        .onChange(of: items) { _, newItems in loadItems(newItems) }
        .task(id: m.message) {
            if m.message != nil {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                m.message = nil
            }
        }
        .sheet(isPresented: $showLayers) { LayersSheet(m: m) }
        .fullScreenCover(isPresented: $showSmartcut) {
            if let l = m.selectedLayer {
                let id = l.id
                SmartcutView(image: l.source, startAll: smartcutStartAll) { result in
                    if let r = result {
                        m.update(id) { $0.cut = r }
                        m.refresh(id)
                    }
                    showSmartcut = false
                }
            }
        }
        .fullScreenCover(item: $editorFor) { req in
            NavigationStack {
                EditorScreen(startImage: req.image, onFinish: { img in
                    m.update(req.layerID) { l in
                        l.source = img
                        l.cut = nil
                        l.adjust = Adjust()
                        l.look = .none
                    }
                    m.refresh(req.layerID)
                }, startTab: req.tab)
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            let cs = fitSize(CGSize(width: m.ratio, height: 1), within: CGSize(width: geo.size.width - 16, height: geo.size.height - 16))
            ZStack {
                if m.bg.transparent { checker(cs) }
                CanvasView(layers: m.layers, bg: m.bg, size: cs, gap: m.gap, corner: m.corner)
                    .overlay(gestureLayer(cs))
                    .overlay(HandlesLayer(m: m, cs: cs, mode: tab == .transform ? tmode : nil))
                    .shadow(color: .black.opacity(0.5), radius: 8)
                if m.layers.isEmpty {
                    PhotosPicker(selection: $items, maxSelectionCount: 9, matching: .images) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled").font(.largeTitle)
                            Text("Fotos hinzufügen").bold()
                        }
                        .padding(20)
                        .background(Color.blue.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottom) { canvasControls }
        }
    }

    private func floatBtn(_ icon: String, _ enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body)
                .frame(width: 38, height: 38)
                .foregroundStyle(enabled ? Color.white : Color.gray)
                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        }
        .disabled(!enabled)
    }

    private var canvasControls: some View {
        HStack(alignment: .bottom, spacing: 8) {
            floatBtn("arrow.uturn.backward", m.canUndo) { m.undo() }
            floatBtn("arrow.uturn.forward", m.canRedo) { m.redo() }
            Spacer()
            if !m.layers.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(Array(m.layers.reversed().prefix(3))) { l in
                        Button { m.selected = l.id } label: {
                            Image(uiImage: l.rendered).resizable().scaledToFill()
                                .frame(width: 38, height: 38)
                                .background(Color(white: 0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5)
                                    .stroke(m.selected == l.id ? Color.blue : Color.white.opacity(0.5), lineWidth: 2))
                                .opacity(l.visible ? 1 : 0.4)
                                .overlay(alignment: .topTrailing) {
                                    if l.locked { Image(systemName: "lock.fill").font(.system(size: 9)).padding(2) }
                                }
                        }
                    }
                    HStack(spacing: 6) {
                        Menu {
                            if let id = m.selected, let l = m.layer(id) {
                                Button { m.update(id) { $0.visible.toggle() } } label: {
                                    Label(l.visible ? "Ausblenden" : "Anzeigen", systemImage: l.visible ? "eye.slash" : "eye")
                                }
                                Button { m.duplicate(id) } label: { Label("Kopieren", systemImage: "plus.square.on.square") }
                                Button { m.toggleLock(id) } label: {
                                    Label(l.locked ? "Entsperren" : "Sperren", systemImage: l.locked ? "lock.open" : "lock")
                                }
                                Button(role: .destructive) { m.remove(id) } label: { Label("Löschen", systemImage: "trash") }
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.body)
                                .frame(width: 38, height: 38)
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        }
                        PhotosPicker(selection: $items, maxSelectionCount: 9, matching: .images) {
                            Image(systemName: "plus").font(.body)
                                .frame(width: 38, height: 38)
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(8)
    }

    private func checker(_ cs: CGSize) -> some View {
        PatternView(index: 2, c1: Color(white: 0.25), c2: Color(white: 0.35))
            .frame(width: cs.width, height: cs.height)
    }

    private func gestureLayer(_ cs: CGSize) -> some View {
        Color.clear.contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        guard let id = m.selected, let l = m.layer(id), !l.locked else { return }
                        if dragStart == nil { dragStart = l.offset }
                        let s = dragStart ?? .zero
                        m.update(id) {
                            $0.offset = CGSize(width: s.width + v.translation.width / cs.width,
                                               height: s.height + v.translation.height / cs.width)
                        }
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        guard let id = m.selected, let l = m.layer(id), !l.locked else { return }
                        if scaleStart == nil { scaleStart = l.scale }
                        let s = scaleStart ?? 1
                        m.update(id) { $0.scale = max(0.1, min(8, s * v.magnification)) }
                    }
                    .onEnded { _ in scaleStart = nil }
            )
            .simultaneousGesture(
                RotateGesture()
                    .onChanged { v in
                        guard let id = m.selected, let l = m.layer(id), !l.locked else { return }
                        if rotStart == nil { rotStart = l.rotation }
                        let s = rotStart ?? .zero
                        m.update(id) { $0.rotation = s + v.rotation }
                    }
                    .onEnded { _ in rotStart = nil }
            )
            .simultaneousGesture(
                SpatialTapGesture().onEnded { v in m.hit(v.location, canvas: cs) }
            )
    }

    // MARK: Laden / Speichern

    private func loadItems(_ newItems: [PhotosPickerItem]) {
        guard !newItems.isEmpty else { return }
        Task {
            var imgs: [UIImage] = []
            for it in newItems {
                if let d = try? await it.loadTransferable(type: Data.self),
                   let img = preparedImage(from: d, maxSide: 1600) { imgs.append(img) }
            }
            m.add(imgs)
            items = []
        }
    }

    private func save() {
        guard let img = m.exportImage() else { m.message = "Export fehlgeschlagen"; return }
        PhotoSaver.save(img, png: m.bg.transparent) { ok in
            m.message = ok ? "In Fotos gesichert" : "Speichern nicht erlaubt"
        }
    }

    // MARK: Panels

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CTab.allCases, id: \.self) { t in
                    Button { tab = t } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.icon).font(.title3)
                            Text(t.title).font(.caption2)
                        }
                        .frame(width: 82)
                        .foregroundStyle(tab == t ? Color.blue : Color.white)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .background(Color.black)
    }

    @ViewBuilder private var panel: some View {
        switch tab {
        case .aspect: AspectPanel(m: m)
        case .grid: GridPanel(m: m)
        case .cutout: CutoutLayerPanel(m: m, openSmartcut: { all in smartcutStartAll = all; showSmartcut = true })
        case .edit: EditLayerPanel(m: m, items: $items, openEditor: { img, id, t in editorFor = EditorRequest(image: img, layerID: id, tab: t) })
        case .transform: TransformPanel(m: m, mode: $tmode)
        case .background: BackgroundPanel(m: m)
        case .text: TextPanel(m: m)
        case .sticker: StickerPanel(m: m)
        }
    }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    let image: UIImage
    let layerID: UUID
    let tab: EditorTab
}

// MARK: - Panels

struct AspectPanel: View {
    @ObservedObject var m: CombineModel
    @State private var category: AspectCategory?

    var body: some View {
        VStack(spacing: 8) {
            if let cat = category {
                HStack {
                    Button { category = nil } label: { Image(systemName: "chevron.left") }
                    Text(cat.name).bold()
                    Spacer()
                }
                .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(cat.presets) { p in
                            Button { m.ratio = p.ratio; m.aspectName = p.name } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(m.aspectName == p.name ? Color.blue : Color.white, lineWidth: 2)
                                            .frame(width: p.ratio >= 1 ? 56 : 56 * p.ratio, height: p.ratio >= 1 ? 56 / p.ratio : 56)
                                    }
                                    .frame(width: 70, height: 70)
                                    Text(p.name).font(.caption2).multilineTextAlignment(.center)
                                        .frame(width: 84, height: 30)
                                }
                                .foregroundStyle(m.aspectName == p.name ? Color.blue : Color.white)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                Text("Seitenverhältnis").bold().padding(.top, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(aspectCategories) { c in
                            Button { category = c } label: {
                                VStack(spacing: 0) {
                                    ZStack {
                                        LinearGradient(colors: c.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                        Image(systemName: c.icon).font(.largeTitle).foregroundStyle(.white)
                                    }
                                    .frame(width: 118, height: 100)
                                    Text(c.name).font(.caption).frame(width: 118, height: 30)
                                        .background(Color(white: 0.15))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct TemplateThumb: View {
    let t: CollageTemplate
    let active: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.15))
            if t == .free {
                Image(systemName: "hand.draw").foregroundStyle(active ? Color.blue : Color.white)
            } else {
                GeometryReader { g in
                    ForEach(Array(t.cells.enumerated()), id: \.offset) { _, c in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(active ? Color.blue : Color.white.opacity(0.8))
                            .frame(width: c.width * (g.size.width - 12) - 2, height: c.height * (g.size.height - 12) - 2)
                            .position(x: 6 + c.midX * (g.size.width - 12), y: 6 + c.midY * (g.size.height - 12))
                    }
                }
            }
        }
        .frame(width: 58, height: 58)
    }
}

struct GridPanel: View {
    @ObservedObject var m: CombineModel

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CollageTemplate.allCases) { t in
                        Button { m.applyTemplate(t) } label: {
                            VStack(spacing: 4) {
                                TemplateThumb(t: t, active: m.template == t)
                                Text(t.title).font(.caption2).frame(width: 70)
                                    .foregroundStyle(m.template == t ? Color.blue : Color.white)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            HStack { Text("Abstand").font(.footnote).frame(width: 70, alignment: .leading); Slider(value: $m.gap, in: 0...0.08) }
                .padding(.horizontal)
            HStack { Text("Ecken").font(.footnote).frame(width: 70, alignment: .leading); Slider(value: $m.corner, in: 0...0.12) }
                .padding(.horizontal)
        }
        .padding(.top, 12)
    }
}

struct CutoutLayerPanel: View {
    @ObservedObject var m: CombineModel
    let openSmartcut: (Bool) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Ausschnitt").bold().padding(.top, 8)
            if let l = m.selectedLayer {
                HStack(spacing: 12) {
                    tile("Keine", "nosign", l.cut == nil) { m.clearCutout(l.id) }
                    tile("Thema", "person.crop.rectangle", false) { m.autoCutout(l.id) }
                    tile("Benutzerdef.", "plus", false) { openSmartcut(true) }
                    tile("Weitere Objekte", "square.on.square.dashed", false) { openSmartcut(false) }
                }
                Text("Thema = automatisch. Benutzerdef. = Smartcut/Pinsel/Verfeinern.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Wähle zuerst eine Ebene aus.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func tile(_ title: String, _ icon: String, _ active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    Color(white: 0.15)
                    Image(systemName: icon).font(.title)
                }
                .frame(width: 78, height: 78)
                Text(title).font(.caption2).frame(width: 78, height: 28)
                    .background(active ? Color.blue : Color(white: 0.12))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
        }
    }
}

enum LayerEditTool { case looks, adjust }

struct EditLayerPanel: View {
    @ObservedObject var m: CombineModel
    @Binding var items: [PhotosPickerItem]
    let openEditor: (UIImage, UUID, EditorTab) -> Void
    @State private var sub = 0
    @State private var tool: LayerEditTool?
    @State private var sel = adjSpecs[0].id
    @State private var thumbs: [LookFilter: UIImage] = [:]

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $sub) {
                Text("Bearb.").tag(0)
                Text("Drehen").tag(1)
                Text("Mischen").tag(2)
            }
            .pickerStyle(.segmented).padding(.horizontal).padding(.top, 8)

            if let l = m.selectedLayer {
                switch sub {
                case 0: editTab(l)
                case 1: rotateTab(l)
                default: blendTab(l)
                }
            } else {
                Spacer()
                Text("Wähle zuerst eine Ebene aus (antippen oder über die Ebenen-Liste).")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                Spacer()
            }
        }
        .onChange(of: m.selected) { _, _ in tool = nil }
    }

    // Bearb.
    @ViewBuilder private func editTab(_ l: CLayer) -> some View {
        if tool == .looks {
            looksView(l)
        } else if tool == .adjust {
            adjustView(l)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    toolTile("Looks", "circle.hexagongrid") { tool = .looks; makeThumbs(l) }
                    toolTile("Änderungen", "slider.horizontal.3") { tool = .adjust }
                    toolTile("Korrigieren", "bandage") { openEditor(l.cut ?? l.source, l.id, .fix) }
                    toolTile("Zuschneiden", "crop") { openEditor(l.cut ?? l.source, l.id, .crop) }
                    PhotosPicker(selection: $items, maxSelectionCount: 9, matching: .images) {
                        tileLabel("Objekte einfügen", "plus.square.on.square")
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func toolTile(_ t: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(t, icon) }
    }

    private func tileLabel(_ t: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15))
                Image(systemName: icon).font(.title2)
            }
            .frame(width: 70, height: 70)
            Text(t).font(.caption2).frame(width: 78, height: 28)
        }
        .foregroundStyle(.white)
    }

    private func makeThumbs(_ l: CLayer) {
        let src = l.cut ?? l.source
        guard let cg = src.cgImage else { return }
        let c = CIImage(cgImage: cg)
        let s = 120 / max(c.extent.width, c.extent.height)
        let small = c.transformed(by: CGAffineTransform(scaleX: s, y: s))
        var out: [LookFilter: UIImage] = [:]
        for lf in LookFilter.allCases {
            let r = lf.apply(small).cropped(to: small.extent)
            if let g = sharedCI.createCGImage(r, from: small.extent) { out[lf] = UIImage(cgImage: g) }
        }
        thumbs = out
    }

    private func backBar(_ title: String) -> some View {
        HStack {
            Button { tool = nil } label: { Image(systemName: "chevron.left") }
            Text(title).bold()
            Spacer()
        }
        .padding(.horizontal)
    }

    private func looksView(_ l: CLayer) -> some View {
        VStack(spacing: 6) {
            backBar("Looks")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(LookFilter.allCases) { lf in
                        Button {
                            m.update(l.id) { $0.look = lf }
                            m.refresh(l.id)
                        } label: {
                            VStack(spacing: 3) {
                                ZStack {
                                    if let t = thumbs[lf] { Image(uiImage: t).resizable().scaledToFill() } else { Color.gray.opacity(0.3) }
                                }
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(l.look == lf ? Color.blue : Color.clear, lineWidth: 3))
                                Text(lf.title).font(.caption2).foregroundStyle(l.look == lf ? Color.blue : Color.white)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            Slider(value: Binding(get: { l.lookAmount }, set: { v in m.update(l.id) { $0.lookAmount = v }; m.refresh(l.id) }), in: 0...1)
                .padding(.horizontal)
        }
    }

    private func adjustView(_ l: CLayer) -> some View {
        let spec = adjSpecs.first { $0.id == sel } ?? adjSpecs[0]
        return VStack(spacing: 6) {
            backBar("Änderungen")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(adjSpecs) { s in
                        Button { sel = s.id } label: {
                            Text(s.name).font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(sel == s.id ? Color.blue.opacity(0.6) : Color(white: 0.15), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                Slider(value: Binding(get: { l.adjust[keyPath: spec.keyPath] },
                                      set: { v in m.update(l.id) { $0.adjust[keyPath: spec.keyPath] = v }; m.refresh(l.id) }),
                       in: spec.range)
                Text("\(Int((l.adjust[keyPath: spec.keyPath] * 100).rounded()))").monospacedDigit().frame(width: 44)
            }
            .padding(.horizontal)
        }
    }

    // Drehen
    private func rotateTab(_ l: CLayer) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Drehen").font(.footnote).frame(width: 70, alignment: .leading)
                Slider(value: Binding(get: { l.rotation.degrees }, set: { v in m.update(l.id) { $0.rotation = .degrees(v) } }), in: -180...180)
            }
            .padding(.horizontal)
            HStack {
                Text("Größe").font(.footnote).frame(width: 70, alignment: .leading)
                Slider(value: Binding(get: { Double(l.scale) }, set: { v in m.update(l.id) { $0.scale = CGFloat(v) } }), in: 0.1...4)
            }
            .padding(.horizontal)
            HStack(spacing: 14) {
                small("90°", "rotate.right") { m.update(l.id) { $0.rotation = $0.rotation + .degrees(90) } }
                small("Spiegeln", "arrow.left.and.right.righttriangle.left.righttriangle.right") { m.update(l.id) { $0.flipH.toggle() } }
                small("Zurücksetzen", "arrow.counterclockwise") { m.resetTransform(l.id) }
            }
        }
        .padding(.top, 8)
    }

    private func small(_ t: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(t, systemImage: icon).font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(white: 0.18), in: Capsule())
                .foregroundStyle(.white)
        }
    }

    // Mischen
    private func blendTab(_ l: CLayer) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Deckkraft").font(.footnote).frame(width: 70, alignment: .leading)
                Slider(value: Binding(get: { l.opacity }, set: { v in m.update(l.id) { $0.opacity = v } }), in: 0.05...1)
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BlendChoice.allCases) { b in
                        Button { m.update(l.id) { $0.blend = b } } label: {
                            Text(b.title).font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(l.blend == b ? Color.blue.opacity(0.6) : Color(white: 0.15), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }
}

struct BackgroundPanel: View {
    @ObservedObject var m: CombineModel
    @State private var sub = 0
    private let swatches: [Color] = [.white, .black, Color(white: 0.5), .red, .orange, .yellow, .green, .mint, .teal, .blue, .indigo, .purple, .pink, .brown]

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $sub) {
                Text("Muster").tag(0)
                Text("Farbverläufe").tag(1)
                Text("Farben").tag(2)
            }
            .pickerStyle(.segmented).padding(.horizontal).padding(.top, 8)

            if sub == 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<patternNames.count, id: \.self) { i in
                            Button { m.bg.kind = .pattern(i); m.bg.transparent = false } label: {
                                VStack(spacing: 0) {
                                    PatternView(index: i, c1: m.bg.color, c2: m.bg.color2).frame(width: 80, height: 80)
                                    Text(patternNames[i]).font(.caption2).frame(width: 80, height: 24).background(Color(white: 0.15))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                HStack {
                    ColorPicker("Farbe 1", selection: $m.bg.color)
                    ColorPicker("Farbe 2", selection: $m.bg.color2)
                }
                .font(.footnote).padding(.horizontal)
            } else if sub == 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<gradientPresets.count, id: \.self) { i in
                            Button { m.bg.kind = .gradient(i); m.bg.transparent = false } label: {
                                LinearGradient(colors: gradientPresets[i], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<swatches.count, id: \.self) { i in
                            Button { m.bg.kind = .color; m.bg.color = swatches[i]; m.bg.transparent = false } label: {
                                Circle().fill(swatches[i]).frame(width: 44, height: 44)
                                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                HStack {
                    ColorPicker("Eigene Farbe", selection: Binding(get: { m.bg.color }, set: { m.bg.color = $0; m.bg.kind = .color; m.bg.transparent = false }))
                    Toggle("Transparent", isOn: $m.bg.transparent)
                }
                .font(.footnote).padding(.horizontal)
            }
            Spacer(minLength: 0)
        }
    }
}

struct TextPanel: View {
    @ObservedObject var m: CombineModel
    @State private var spec = TextSpec()
    @State private var editingID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            Text(editingID == nil ? "Neuer Text" : "Text bearbeiten").bold().padding(.top, 8)
            TextField("Text eingeben", text: $spec.text)
                .textFieldStyle(.roundedBorder).padding(.horizontal)
            Picker("", selection: $spec.fontIndex) {
                Text("Standard").tag(0); Text("Rund").tag(1); Text("Serif").tag(2); Text("Mono").tag(3)
            }
            .pickerStyle(.segmented).padding(.horizontal)
            HStack {
                ColorPicker("", selection: $spec.color).labelsHidden()
                Toggle("Fett", isOn: $spec.bold).fixedSize()
                Toggle("Kontur", isOn: $spec.outline).fixedSize()
                Spacer()
                Button(editingID == nil ? "Hinzufügen" : "Übernehmen") {
                    if let id = editingID { m.updateText(id, spec) } else { m.addText(spec) }
                }
                .bold()
            }
            .font(.footnote).padding(.horizontal)
        }
        .onChange(of: m.selected) { _, id in
            if let l = m.layer(id), let t = l.text { spec = t; editingID = l.id } else { editingID = nil }
        }
    }
}

struct StickerPanel: View {
    @ObservedObject var m: CombineModel
    private let emojis = "😀😂😍😎🥳😭😡🤔👍👏🙏💪🔥✨⭐️🌈❤️💙💚💛🧡💜🖤🎉🎈🎁🏆👑💎🌸🌻🌴🌞🌙☁️⚡️❄️🍕🍔🍟🍩🍦🍎🍓🥑☕️🎵🎶📷🚗✈️🏠🐶🐱🦊🐼🦋🐢🦄👻💀👽🤖".map { String($0) }
    private let symbols = ["heart.fill", "star.fill", "bolt.fill", "flame.fill", "sparkles", "moon.fill", "sun.max.fill", "cloud.fill", "leaf.fill", "crown.fill", "flag.fill", "bell.fill", "hand.thumbsup.fill", "location.fill", "gift.fill", "camera.fill"]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                ForEach(emojis, id: \.self) { e in
                    Button { add(renderEmoji(e), "Sticker") } label: { Text(e).font(.title2) }
                }
                ForEach(symbols, id: \.self) { s in
                    Button { add(renderSymbol(s, color: .systemYellow), "Symbol") } label: {
                        Image(systemName: s).font(.title3).foregroundStyle(.yellow)
                    }
                }
            }
            .padding()
        }
    }

    private func add(_ img: UIImage, _ name: String) {
        var l = CLayer(name: name, image: img)
        l.scale = 0.5
        m.layers.append(l)
        m.selected = l.id
    }
}

enum TMode: String, CaseIterable, Identifiable {
    case free, skew, distort, perspective
    var id: String { rawValue }
    var title: String {
        switch self {
        case .free: return "Freiform"
        case .skew: return "Neigen"
        case .distort: return "Verzerrung"
        case .perspective: return "Perspektive"
        }
    }
    var icon: String {
        switch self {
        case .free: return "arrow.up.left.and.arrow.down.right"
        case .skew: return "square.slash"
        case .distort: return "skew"
        case .perspective: return "perspective"
        }
    }
}

struct TransformPanel: View {
    @ObservedObject var m: CombineModel
    @Binding var mode: TMode

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ForEach(TMode.allCases) { t in
                    Button { mode = t } label: {
                        VStack(spacing: 6) {
                            Image(systemName: t.icon).font(.title3)
                                .frame(width: 58, height: 52)
                                .background(mode == t ? Color.blue : Color(white: 0.18), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                            Text(t.title).font(.caption2)
                                .foregroundStyle(mode == t ? Color.blue : Color.white)
                        }
                    }
                }
            }
            Text(mode == .free ? "Ecken ziehen: Breite und Höhe frei ändern."
                 : mode == .skew ? "Ecken ziehen: Ebene neigen."
                 : mode == .distort ? "Jede Ecke einzeln verschieben."
                 : "Ecken ziehen: Perspektive ändern.")
                .font(.caption).foregroundStyle(.secondary)
            if let id = m.selected {
                Button("Transformation zurücksetzen") { m.resetTransform(id) }.font(.footnote)
            }
        }
        .padding(.top, 14)
    }
}

struct HandlesLayer: View {
    @ObservedObject var m: CombineModel
    let cs: CGSize
    let mode: TMode?
    @State private var start: CLayer?

    private let signs: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]

    private func baseSize(_ l: CLayer) -> CGSize {
        fitSize(l.rendered.size, within: CGSize(width: cs.width * 0.6, height: cs.height * 0.6))
    }
    private func dims(_ l: CLayer) -> CGSize {
        let b = baseSize(l)
        return CGSize(width: b.width * l.scale * l.stretch.width, height: b.height * l.scale * l.stretch.height)
    }
    private func center(_ l: CLayer) -> CGPoint {
        CGPoint(x: cs.width / 2 + l.offset.width * cs.width, y: cs.height / 2 + l.offset.height * cs.width)
    }
    private func rot(_ p: CGPoint, _ a: Double) -> CGPoint {
        CGPoint(x: p.x * cos(a) - p.y * sin(a), y: p.x * sin(a) + p.y * cos(a))
    }
    private func handlePos(_ l: CLayer, _ i: Int) -> CGPoint {
        let d = dims(l)
        let fx: CGFloat = l.flipH ? -1 : 1
        let q = l.quad[i]
        let local = CGPoint(x: fx * (signs[i].0 * d.width / 2 + q.x * d.width),
                            y: signs[i].1 * d.height / 2 + q.y * d.height)
        let r = rot(local, l.rotation.radians)
        let c = center(l)
        return CGPoint(x: c.x + r.x, y: c.y + r.y)
    }

    var body: some View {
        ZStack {
            if let l = m.selectedLayer, l.cell == nil, l.visible, !l.locked {
                let pts = (0..<4).map { handlePos(l, $0) }
                Path { p in
                    p.move(to: pts[0])
                    for q in pts.dropFirst() { p.addLine(to: q) }
                    p.closeSubpath()
                }
                .stroke(Color.white, lineWidth: 1.5).allowsHitTesting(false)
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(Color.white)
                        .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .position(pts[i])
                        .gesture(drag(i, l.id))
                }
            }
        }
        .frame(width: cs.width, height: cs.height)
        .coordinateSpace(name: "cv")
    }

    private func drag(_ i: Int, _ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("cv"))
            .onChanged { v in
                if start == nil { start = m.layer(id) }
                guard let s = start else { return }
                apply(i, id, s, v)
            }
            .onEnded { _ in
                start = nil
                if mode != nil && mode != .free { m.rewarp(id) }
            }
    }

    private func apply(_ i: Int, _ id: UUID, _ s: CLayer, _ v: DragGesture.Value) {
        let a = s.rotation.radians
        let dl = rot(CGPoint(x: v.translation.width, y: v.translation.height), -a)
        let fx: CGFloat = s.flipH ? -1 : 1
        let d = dims(s)
        guard d.width > 1, d.height > 1 else { return }
        let sx = signs[i].0, sy = signs[i].1
        func clamp(_ x: CGFloat) -> CGFloat { min(0.5, max(-0.5, x)) }

        guard let mode else {
            let c = center(s)
            let d0 = hypot(v.startLocation.x - c.x, v.startLocation.y - c.y)
            let d1 = hypot(v.location.x - c.x, v.location.y - c.y)
            guard d0 > 1 else { return }
            m.update(id) { $0.scale = max(0.1, min(8, s.scale * d1 / d0)) }
            return
        }
        let dxf = fx * dl.x / d.width
        let dyf = dl.y / d.height
        switch mode {
        case .free:
            let sdx = fx * sx
            let nw = max(20, d.width + sdx * dl.x)
            let nh = max(20, d.height + sy * dl.y)
            let shiftLocal = CGPoint(x: (nw - d.width) / 2 * sdx, y: (nh - d.height) / 2 * sy)
            let sh = rot(shiftLocal, a)
            m.update(id) {
                $0.stretch = CGSize(width: s.stretch.width * nw / d.width, height: s.stretch.height * nh / d.height)
                $0.offset = CGSize(width: s.offset.width + sh.x / cs.width, height: s.offset.height + sh.y / cs.width)
            }
        case .skew:
            var q = s.quad
            let ax = dxf * (-sy)
            let ay = dyf * sx
            for k in 0..<4 {
                q[k].x = clamp(q[k].x + (signs[k].1 < 0 ? ax / 2 : -ax / 2))
                q[k].y = clamp(q[k].y + (signs[k].0 > 0 ? ay / 2 : -ay / 2))
            }
            m.update(id) { $0.quad = q }
            m.rewarp(id)
        case .distort:
            var q = s.quad
            q[i] = CGPoint(x: clamp(q[i].x + dxf), y: clamp(q[i].y + dyf))
            m.update(id) { $0.quad = q }
            m.rewarp(id)
        case .perspective:
            var q = s.quad
            let n = [1, 0, 3, 2][i]
            q[i] = CGPoint(x: clamp(q[i].x + dxf), y: clamp(q[i].y + dyf))
            q[n] = CGPoint(x: clamp(q[n].x - dxf), y: clamp(q[n].y + dyf))
            m.update(id) { $0.quad = q }
            m.rewarp(id)
        }
    }
}

struct LayersSheet: View {
    @ObservedObject var m: CombineModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(m.layers.reversed())) { l in
                    HStack(spacing: 12) {
                        Image(uiImage: l.rendered).resizable().scaledToFit()
                            .frame(width: 44, height: 44)
                            .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 6))
                        Text(l.name).foregroundStyle(m.selected == l.id ? Color.blue : Color.primary)
                        Spacer()
                        Button { m.update(l.id) { $0.visible.toggle() } } label: {
                            Image(systemName: l.visible ? "eye" : "eye.slash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { m.selected = l.id }
                    .swipeActions {
                        Button(role: .destructive) { m.remove(l.id) } label: { Label("Löschen", systemImage: "trash") }
                        Button { m.duplicate(l.id) } label: { Label("Duplizieren", systemImage: "plus.square.on.square") }.tint(.blue)
                    }
                }
                .onMove { from, to in
                    var rev = Array(m.layers.reversed())
                    rev.move(fromOffsets: from, toOffset: to)
                    m.layers = Array(rev.reversed())
                    m.assignCells(reset: false)
                }
            }
            .navigationTitle("Ebenen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
