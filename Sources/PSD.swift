import SwiftUI
import PhotosUI
import Compression
import UniformTypeIdentifiers

// MARK: - Datenmodell

struct PLayer: Identifiable {
    enum Kind { case raster, groupStart, groupEnd }
    let id = UUID()
    var name: String
    var kind: Kind = .raster
    var image: UIImage?
    var origin: CGPoint = .zero
    var opacity: Double = 1
    var blendKey = "norm"
    var visible = true
}

indirect enum PNode {
    case layer(PLayer)
    case group(PLayer, [PNode])
}

struct PSDDocument: @unchecked Sendable {
    var canvas: CGSize
    var layers: [PLayer]          // von unten nach oben (wie in der Datei)
    var notes: [String]
}

let psdBlendModes: [(String, String)] = [
    ("norm", "Normal"), ("mul ", "Multiplizieren"), ("scrn", "Negativ multipl."), ("over", "Ineinanderkopieren"),
    ("sLit", "Weiches Licht"), ("hLit", "Hartes Licht"), ("dark", "Abdunkeln"), ("lite", "Aufhellen"),
    ("div ", "Abwedeln"), ("idiv", "Nachbelichten"), ("diff", "Differenz"), ("smud", "Ausschluss"),
    ("hue ", "Farbton"), ("sat ", "Sättigung"), ("colr", "Farbe"), ("lum ", "Luminanz")
]

func cgBlend(_ key: String) -> CGBlendMode {
    switch key {
    case "mul ", "lbrn": return .multiply
    case "scrn": return .screen
    case "over": return .overlay
    case "dark": return .darken
    case "lite": return .lighten
    case "div ": return .colorDodge
    case "idiv": return .colorBurn
    case "sLit": return .softLight
    case "hLit": return .hardLight
    case "diff": return .difference
    case "smud": return .exclusion
    case "hue ": return .hue
    case "sat ": return .saturation
    case "colr": return .color
    case "lum ": return .luminosity
    case "lddg": return .plusLighter
    default: return .normal
    }
}

// MARK: - Rendern

func buildTree(_ layers: [PLayer]) -> [PNode] {
    var stack: [[PNode]] = [[]]
    for l in layers {
        switch l.kind {
        case .raster:
            stack[stack.count - 1].append(.layer(l))
        case .groupEnd:
            stack.append([])
        case .groupStart:
            if stack.count > 1 {
                let kids = stack.removeLast()
                stack[stack.count - 1].append(.group(l, kids))
            }
        }
    }
    while stack.count > 1 {
        let kids = stack.removeLast()
        stack[stack.count - 1].append(contentsOf: kids)
    }
    return stack[0]
}

func drawNodes(_ nodes: [PNode], canvas: CGSize, scale: CGFloat) {
    for n in nodes {
        switch n {
        case .layer(let l):
            guard l.visible, let img = l.image else { continue }
            img.draw(in: CGRect(origin: l.origin, size: img.size), blendMode: cgBlend(l.blendKey), alpha: CGFloat(l.opacity))
        case .group(let g, let kids):
            guard g.visible else { continue }
            if g.blendKey == "pass" && g.opacity >= 0.999 {
                drawNodes(kids, canvas: canvas, scale: scale)
            } else {
                let off = renderNodes(kids, canvas: canvas, scale: scale, bg: nil)
                let key = g.blendKey == "pass" ? "norm" : g.blendKey
                off.draw(in: CGRect(origin: .zero, size: canvas), blendMode: cgBlend(key), alpha: CGFloat(g.opacity))
            }
        }
    }
}

func renderNodes(_ nodes: [PNode], canvas: CGSize, scale: CGFloat, bg: UIColor?) -> UIImage {
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    fmt.opaque = (bg != nil)
    let size = CGSize(width: max(1, (canvas.width * scale).rounded()), height: max(1, (canvas.height * scale).rounded()))
    return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
        if let bg {
            bg.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        ctx.cgContext.scaleBy(x: scale, y: scale)
        drawNodes(nodes, canvas: canvas, scale: scale)
    }
}

func renderDocument(_ layers: [PLayer], canvas: CGSize, scale: CGFloat, bg: UIColor?) -> UIImage {
    renderNodes(buildTree(layers), canvas: canvas, scale: scale, bg: bg)
}

// MARK: - PSD lesen

struct PSDError: Error { let msg: String }

struct ByteReader {
    let b: [UInt8]
    var p = 0
    init(_ d: [UInt8]) { b = d }

    mutating func u8() throws -> Int {
        guard p < b.count else { throw PSDError(msg: "Datei ist unvollständig.") }
        let v = Int(b[p])
        p += 1
        return v
    }
    mutating func u16() throws -> Int { let a = try u8(); let c = try u8(); return (a << 8) | c }
    mutating func i16() throws -> Int { let v = try u16(); return v >= 0x8000 ? v - 0x10000 : v }
    mutating func u32() throws -> Int { let a = try u16(); let c = try u16(); return (a << 16) | c }
    mutating func i32() throws -> Int { let v = try u32(); return v >= 0x8000_0000 ? v - 0x1_0000_0000 : v }
    mutating func skip(_ n: Int) throws {
        guard n >= 0, p + n <= b.count else { throw PSDError(msg: "Datei ist unvollständig.") }
        p += n
    }
    mutating func str(_ n: Int) throws -> String {
        guard n >= 0, p + n <= b.count else { throw PSDError(msg: "Datei ist unvollständig.") }
        let s = String(bytes: b[p..<(p + n)], encoding: .macOSRoman) ?? ""
        p += n
        return s
    }
}

struct PSDRecord {
    var top = 0, left = 0, bottom = 0, right = 0
    var channels: [(id: Int, len: Int)] = []
    var blendKey = "norm"
    var opacity = 255
    var flags = 0
    var name = ""
    var section = 0
    var maskTop = 0, maskLeft = 0, maskBottom = 0, maskRight = 0
    var maskDefault = 0
    var maskDisabled = false
    var width: Int { max(0, right - left) }
    var height: Int { max(0, bottom - top) }
}

enum PSDParser {
    static func unpackBits(_ src: ArraySlice<UInt8>, expected: Int) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(expected)
        var i = src.startIndex
        while i < src.endIndex && out.count < expected {
            let n = Int(Int8(bitPattern: src[i]))
            i += 1
            if n >= 0 {
                let end = min(i + n + 1, src.endIndex)
                out.append(contentsOf: src[i..<end])
                i = end
            } else if n != -128 {
                if i < src.endIndex {
                    out.append(contentsOf: repeatElement(src[i], count: 1 - n))
                    i += 1
                }
            }
        }
        if out.count < expected { out.append(contentsOf: repeatElement(0, count: expected - out.count)) }
        if out.count > expected { out.removeLast(out.count - expected) }
        return out
    }

    static func inflate(_ src: ArraySlice<UInt8>, expected: Int) -> [UInt8]? {
        guard src.count > 2, expected > 0 else { return nil }
        let body = Array(src.dropFirst(2))
        var dst = [UInt8](repeating: 0, count: expected)
        let n = body.withUnsafeBufferPointer { sp in
            dst.withUnsafeMutableBufferPointer { dp in
                compression_decode_buffer(dp.baseAddress!, expected, sp.baseAddress!, body.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n > 0 ? dst : nil
    }

    /// Dekodiert einen Kanal (inkl. 2-Byte-Kompressionsfeld) in 8-Bit-Pixel.
    static func decodePlane(_ b: [UInt8], start: Int, length: Int, w: Int, h: Int, depth: Int) -> [UInt8]? {
        guard length >= 2, start + length <= b.count, w > 0, h > 0 else { return nil }
        let comp = (Int(b[start]) << 8) | Int(b[start + 1])
        let ds = start + 2
        let de = start + length
        let bpp = depth / 8
        let rowBytes = w * bpp
        var raw: [UInt8]
        switch comp {
        case 0:
            raw = Array(b[ds..<min(de, ds + rowBytes * h)])
        case 1:
            guard ds + 2 * h <= de else { return nil }
            var tp = ds
            var dp = ds + 2 * h
            raw = []
            raw.reserveCapacity(rowBytes * h)
            for _ in 0..<h {
                let cnt = (Int(b[tp]) << 8) | Int(b[tp + 1])
                tp += 2
                let end = min(dp + cnt, de)
                raw.append(contentsOf: unpackBits(b[dp..<end], expected: rowBytes))
                dp = end
            }
        case 2, 3:
            guard var r = inflate(b[ds..<de], expected: rowBytes * h) else { return nil }
            if comp == 3 {
                if depth == 8 {
                    for y in 0..<h {
                        let o = y * w
                        for x in 1..<max(w, 1) { r[o + x] = r[o + x] &+ r[o + x - 1] }
                    }
                } else if depth == 16 {
                    for y in 0..<h {
                        let o = y * rowBytes
                        var prev = 0
                        for x in 0..<w {
                            let cur = (((Int(r[o + 2 * x]) << 8) | Int(r[o + 2 * x + 1])) + prev) & 0xFFFF
                            prev = cur
                            r[o + 2 * x] = UInt8(cur >> 8)
                            r[o + 2 * x + 1] = UInt8(cur & 0xFF)
                        }
                    }
                }
            }
            raw = r
        default:
            return nil
        }
        if raw.count < rowBytes * h { raw.append(contentsOf: repeatElement(0, count: rowBytes * h - raw.count)) }
        if depth == 16 {
            var out = [UInt8](repeating: 0, count: w * h)
            for i in 0..<(w * h) { out[i] = raw[i * 2] }
            return out
        }
        return Array(raw[0..<(w * h)])
    }

    static func makeImage(rgb: [[UInt8]], alpha: [UInt8]?, w: Int, h: Int, rec: PSDRecord, maskPlane: [UInt8]?) -> UIImage? {
        guard w > 0, h > 0, rgb.count == 3 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let mw = max(0, rec.maskRight - rec.maskLeft)
        let mh = max(0, rec.maskBottom - rec.maskTop)
        let useMask = maskPlane != nil && mw > 0 && mh > 0 && !rec.maskDisabled
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                var a = alpha.map { Int($0[i]) } ?? 255
                if useMask, let mp = maskPlane {
                    let gx = rec.left + x - rec.maskLeft
                    let gy = rec.top + y - rec.maskTop
                    let mv = (gx >= 0 && gy >= 0 && gx < mw && gy < mh) ? Int(mp[gy * mw + gx]) : rec.maskDefault
                    a = a * mv / 255
                }
                let o = i * 4
                buf[o] = UInt8(Int(rgb[0][i]) * a / 255)
                buf[o + 1] = UInt8(Int(rgb[1][i]) * a / 255)
                buf[o + 2] = UInt8(Int(rgb[2][i]) * a / 255)
                buf[o + 3] = UInt8(a)
            }
        }
        guard let provider = CGDataProvider(data: Data(buf) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    static func parse(_ data: Data) throws -> PSDDocument {
        let bytes = [UInt8](data)
        var r = ByteReader(bytes)
        guard try r.str(4) == "8BPS" else { throw PSDError(msg: "Das ist keine PSD-Datei.") }
        let version = try r.u16()
        guard version == 1 else { throw PSDError(msg: "PSB (große Dokumente) wird noch nicht unterstützt.") }
        try r.skip(6)
        let channels = try r.u16()
        let height = try r.u32()
        let width = try r.u32()
        let depth = try r.u16()
        let mode = try r.u16()
        guard depth == 8 || depth == 16 else { throw PSDError(msg: "Nur 8- und 16-Bit-Dateien werden unterstützt.") }
        guard mode == 3 || mode == 1 else { throw PSDError(msg: "Nur RGB- und Graustufen-Dateien werden unterstützt (kein CMYK).") }
        guard width > 0, height > 0, width <= 30000, height <= 30000 else { throw PSDError(msg: "Ungültige Größe.") }

        try r.skip(try r.u32())     // Farbmodus-Daten
        try r.skip(try r.u32())     // Bildressourcen

        var notes: [String] = []
        var layers: [PLayer] = []
        let lmLen = try r.u32()
        let lmEnd = r.p + lmLen

        if lmLen > 0 {
            let liLen = try r.u32()
            let liEnd = r.p + liLen
            if liLen > 0 {
                let count = abs(try r.i16())
                var recs: [PSDRecord] = []
                for _ in 0..<count {
                    var rec = PSDRecord()
                    rec.top = try r.i32(); rec.left = try r.i32(); rec.bottom = try r.i32(); rec.right = try r.i32()
                    let nch = try r.u16()
                    for _ in 0..<nch {
                        let id = try r.i16()
                        let len = try r.u32()
                        rec.channels.append((id, len))
                    }
                    _ = try r.str(4)                     // "8BIM"
                    rec.blendKey = try r.str(4)
                    rec.opacity = try r.u8()
                    _ = try r.u8()                       // Beschneidung
                    rec.flags = try r.u8()
                    _ = try r.u8()
                    let extraLen = try r.u32()
                    let extraEnd = r.p + extraLen

                    let maskLen = try r.u32()
                    if maskLen >= 18 {
                        let mStart = r.p
                        rec.maskTop = try r.i32(); rec.maskLeft = try r.i32(); rec.maskBottom = try r.i32(); rec.maskRight = try r.i32()
                        rec.maskDefault = try r.u8()
                        let mf = try r.u8()
                        rec.maskDisabled = (mf & 2) != 0
                        r.p = mStart + maskLen
                    } else {
                        try r.skip(maskLen)
                    }
                    try r.skip(try r.u32())              // Mischbereiche

                    let nlen = try r.u8()
                    rec.name = try r.str(nlen)
                    try r.skip((4 - (1 + nlen) % 4) % 4)

                    while r.p + 12 <= extraEnd {
                        let sig = try r.str(4)
                        guard sig == "8BIM" || sig == "8B64" else { break }
                        let key = try r.str(4)
                        let blen = try r.u32()
                        let bstart = r.p
                        if key == "lsct", blen >= 4 {
                            rec.section = try r.u32()
                            if blen >= 12 {
                                _ = try r.str(4)
                                let bk = try r.str(4)
                                if rec.section == 1 || rec.section == 2 { rec.blendKey = bk }
                            }
                        } else if key == "luni", blen >= 4 {
                            let n = try r.u32()
                            var scalars: [UInt16] = []
                            for _ in 0..<min(n, 512) { scalars.append(UInt16(try r.u16())) }
                            let s = String(decoding: scalars, as: UTF16.self)
                            if !s.isEmpty { rec.name = s }
                        }
                        r.p = bstart + blen + (blen % 2)
                    }
                    r.p = extraEnd
                    recs.append(rec)
                }

                var skippedAdjustments = 0
                for rec in recs {
                    var planes: [Int: [UInt8]] = [:]
                    for ch in rec.channels {
                        let start = r.p
                        let isMask = ch.id <= -2
                        let cw = isMask ? max(0, rec.maskRight - rec.maskLeft) : rec.width
                        let ch_h = isMask ? max(0, rec.maskBottom - rec.maskTop) : rec.height
                        if cw > 0, ch_h > 0, ch.len >= 2,
                           let plane = decodePlane(bytes, start: start, length: ch.len, w: cw, h: ch_h, depth: depth) {
                            planes[ch.id] = plane
                        }
                        try r.skip(ch.len)
                    }

                    var pl = PLayer(name: rec.name.isEmpty ? "Ebene" : rec.name)
                    pl.opacity = Double(rec.opacity) / 255
                    pl.blendKey = rec.blendKey
                    pl.visible = (rec.flags & 2) == 0
                    pl.origin = CGPoint(x: rec.left, y: rec.top)
                    switch rec.section {
                    case 1, 2: pl.kind = .groupStart
                    case 3: pl.kind = .groupEnd; pl.name = "Ende der Gruppe"
                    default:
                        pl.kind = .raster
                        let w = rec.width, h = rec.height
                        if w > 0, h > 0 {
                            let rgb: [[UInt8]]
                            if mode == 1, let g = planes[0] { rgb = [g, g, g] }
                            else if let rr = planes[0], let gg = planes[1], let bb = planes[2] { rgb = [rr, gg, bb] }
                            else { rgb = [] }
                            pl.image = makeImage(rgb: rgb, alpha: planes[-1], w: w, h: h, rec: rec, maskPlane: planes[-2])
                        }
                        if pl.image == nil {
                            skippedAdjustments += 1
                            continue      // Einstellungs-/leere Ebenen ohne Pixel überspringen
                        }
                    }
                    layers.append(pl)
                }
                if skippedAdjustments > 0 {
                    notes.append("\(skippedAdjustments) Ebene(n) ohne Pixel (z. B. Einstellungsebenen) wurden übersprungen.")
                }
            }
            r.p = lmEnd
        }

        let hasRaster = layers.contains { $0.kind == .raster }
        if !hasRaster {
            // Fallback: zusammengefügtes Bild
            layers = []
            let comp = try r.u16()
            var planes: [[UInt8]] = []
            let n = max(1, min(channels, 4))
            let rowBytes = width * (depth / 8)
            if comp == 0 {
                for _ in 0..<n {
                    let end = r.p + rowBytes * height
                    guard end <= bytes.count else { break }
                    var raw = Array(bytes[r.p..<end])
                    if depth == 16 { raw = stride(from: 0, to: raw.count, by: 2).map { raw[$0] } }
                    planes.append(raw)
                    r.p = end
                }
            } else if comp == 1 {
                var tp = r.p
                var dp = r.p + 2 * height * channels
                for _ in 0..<n {
                    var raw: [UInt8] = []
                    for _ in 0..<height {
                        guard tp + 1 < bytes.count else { break }
                        let cnt = (Int(bytes[tp]) << 8) | Int(bytes[tp + 1])
                        tp += 2
                        let end = min(dp + cnt, bytes.count)
                        raw.append(contentsOf: unpackBits(bytes[dp..<end], expected: rowBytes))
                        dp = end
                    }
                    if depth == 16 { raw = stride(from: 0, to: raw.count, by: 2).map { raw[$0] } }
                    planes.append(raw)
                }
            }
            var rec = PSDRecord()
            rec.right = width; rec.bottom = height
            let ok = planes.count >= (mode == 1 ? 1 : 3) && planes.allSatisfy { $0.count >= width * height }
            if ok {
                let rgb: [[UInt8]] = mode == 1 ? [planes[0], planes[0], planes[0]] : [planes[0], planes[1], planes[2]]
                let alpha: [UInt8]? = (mode == 3 && planes.count >= 4) ? planes[3] : nil
                var bg = PLayer(name: "Hintergrund")
                bg.image = makeImage(rgb: rgb, alpha: alpha, w: width, h: height, rec: rec, maskPlane: nil)
                layers = [bg]
                notes.append("Diese Datei enthält keine einzelnen Ebenen – nur das zusammengefügte Bild.")
            } else {
                throw PSDError(msg: "Das Bild in der Datei konnte nicht gelesen werden.")
            }
        }
        notes.append("Ebenenstile/-effekte, Schnittmasken und Einstellungsebenen werden nicht dargestellt.")
        return PSDDocument(canvas: CGSize(width: width, height: height), layers: layers, notes: notes)
    }
}

// MARK: - PSD schreiben

extension Data {
    mutating func put8(_ v: Int) { append(UInt8(truncatingIfNeeded: v)) }
    mutating func put16(_ v: Int) { put8(v >> 8); put8(v) }
    mutating func put32(_ v: Int) { put16(v >> 16); put16(v) }
    mutating func putStr(_ s: String) { append(contentsOf: Array(s.utf8)) }
}

enum PSDWriter {
    static func rgba(_ img: UIImage) -> (Int, Int, [UInt8])? {
        guard let cg = img.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        // Rückrechnen auf nicht-prämultiplizierte Farben
        for i in 0..<(w * h) {
            let a = Int(buf[i * 4 + 3])
            if a == 0 { buf[i * 4] = 0; buf[i * 4 + 1] = 0; buf[i * 4 + 2] = 0 }
            else if a < 255 {
                for c in 0..<3 { buf[i * 4 + c] = UInt8(min(255, Int(buf[i * 4 + c]) * 255 / a)) }
            }
        }
        return (w, h, buf)
    }

    static func asciiName(_ s: String) -> [UInt8] {
        let folded = s.folding(options: .diacriticInsensitive, locale: .current)
        var out: [UInt8] = []
        for u in folded.unicodeScalars {
            out.append(u.value >= 32 && u.value < 127 ? UInt8(u.value) : UInt8(ascii: "_"))
            if out.count >= 250 { break }
        }
        return out
    }

    static func write(layers: [PLayer], canvas: CGSize) -> Data {
        let cw = Int(canvas.width), ch = Int(canvas.height)
        var records = Data()
        var channelBlob = Data()
        var count = 0

        for l in layers {
            var rec = Data()
            var chanData: [Data] = []
            var top = 0, left = 0, bottom = 0, right = 0
            var key = l.blendKey
            if key.utf8.count != 4 { key = "norm" }
            var nameBytes = asciiName(l.name)
            var section: Int?

            switch l.kind {
            case .raster:
                guard let img = l.image, let px = rgba(img) else { continue }
                let (w, h, buf) = px
                left = Int(l.origin.x.rounded()); top = Int(l.origin.y.rounded())
                right = left + w; bottom = top + h
                var planes = [Data](repeating: Data(), count: 4)   // A, R, G, B
                for i in 0..<4 { planes[i].reserveCapacity(w * h) }
                for i in 0..<(w * h) {
                    planes[1].append(buf[i * 4]); planes[2].append(buf[i * 4 + 1])
                    planes[3].append(buf[i * 4 + 2]); planes[0].append(buf[i * 4 + 3])
                }
                for p in planes { var d = Data(); d.put16(0); d.append(p); chanData.append(d) }
            case .groupStart:
                key = "pass"; section = 1
                for _ in 0..<4 { var d = Data(); d.put16(0); chanData.append(d) }
            case .groupEnd:
                key = "norm"; section = 3; nameBytes = Array("</Layer group>".utf8)
                for _ in 0..<4 { var d = Data(); d.put16(0); chanData.append(d) }
            }

            rec.put32(top); rec.put32(left); rec.put32(bottom); rec.put32(right)
            rec.put16(4)
            let ids = [-1, 0, 1, 2]
            for (i, id) in ids.enumerated() {
                rec.put16(id & 0xFFFF)
                rec.put32(chanData[i].count)
            }
            rec.putStr("8BIM"); rec.putStr(key)
            rec.put8(Int((l.opacity * 255).rounded())); rec.put8(0)
            rec.put8(l.visible ? 0 : 2); rec.put8(0)

            var extra = Data()
            extra.put32(0)      // Ebenenmaske
            extra.put32(0)      // Mischbereiche
            extra.put8(nameBytes.count)
            extra.append(contentsOf: nameBytes)
            let padName = (4 - (1 + nameBytes.count) % 4) % 4
            extra.append(contentsOf: [UInt8](repeating: 0, count: padName))
            if let s = section {
                extra.putStr("8BIM"); extra.putStr("lsct"); extra.put32(4); extra.put32(s)
            }
            rec.put32(extra.count)
            rec.append(extra)

            records.append(rec)
            for d in chanData { channelBlob.append(d) }
            count += 1
        }

        var layerInfo = Data()
        layerInfo.put16(count)
        layerInfo.append(records)
        layerInfo.append(channelBlob)
        if layerInfo.count % 2 == 1 { layerInfo.put8(0) }

        var out = Data()
        out.putStr("8BPS"); out.put16(1)
        out.append(contentsOf: [UInt8](repeating: 0, count: 6))
        out.put16(3); out.put32(ch); out.put32(cw); out.put16(8); out.put16(3)
        out.put32(0)        // Farbmodus-Daten
        out.put32(0)        // Bildressourcen
        out.put32(4 + layerInfo.count + 4)
        out.put32(layerInfo.count)
        out.append(layerInfo)
        out.put32(0)        // globale Maske

        // zusammengefügtes Bild (auf Weiß)
        let flat = renderDocument(layers, canvas: canvas, scale: 1, bg: .white)
        out.put16(0)
        if let px = rgba(flat), px.0 == cw, px.1 == ch {
            let buf = px.2
            for c in 0..<3 {
                var plane = Data(capacity: cw * ch)
                for i in 0..<(cw * ch) { plane.append(buf[i * 4 + c]) }
                out.append(plane)
            }
        } else {
            out.append(Data(repeating: 255, count: cw * ch * 3))
        }
        return out
    }
}

// MARK: - Modell

enum PTab: String, CaseIterable {
    case move, brush, adjust, transform, more
    var title: String {
        switch self {
        case .move: return "Ebene"
        case .brush: return "Pinsel"
        case .adjust: return "Anpassen"
        case .transform: return "Transform."
        case .more: return "Mehr"
        }
    }
    var icon: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .brush: return "paintbrush.pointed"
        case .adjust: return "slider.horizontal.3"
        case .transform: return "crop.rotate"
        case .more: return "ellipsis.circle"
        }
    }
}

@MainActor
final class PSDModel: ObservableObject {
    @Published var layers: [PLayer] = []
    @Published var selected: UUID?
    @Published var canvas: CGSize = .zero
    @Published var preview: UIImage?
    @Published var busy = false
    @Published var message: String?
    @Published var canUndo = false
    var fileName = "Dokument"
    var notes: [String] = []

    private var undoStack: [[PLayer]] = []
    private var adjustBase: UIImage?
    private var adjustTarget: UUID?

    var hasDoc: Bool { canvas.width > 0 }
    var selectedLayer: PLayer? { layers.first { $0.id == selected } }
    var selectedRaster: PLayer? { if let l = selectedLayer, l.kind == .raster { return l } else { return nil } }

    func open(_ doc: PSDDocument, name: String) {
        canvas = doc.canvas
        layers = doc.layers
        notes = doc.notes
        fileName = name
        undoStack = []
        canUndo = false
        selected = layers.last(where: { $0.kind == .raster })?.id
        rerender()
    }

    func newDocument(width: Int, height: Int) {
        canvas = CGSize(width: width, height: height)
        fileName = "Neu"
        var bg = PLayer(name: "Hintergrund")
        bg.image = Self.solid(size: canvas, color: .white)
        layers = [bg]
        selected = bg.id
        undoStack = []
        canUndo = false
        rerender()
    }

    static func solid(size: CGSize, color: UIColor) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func rerender() {
        guard hasDoc else { return }
        let s = min(1, 1400 / max(canvas.width, canvas.height))
        preview = renderDocument(layers, canvas: canvas, scale: s, bg: nil)
    }

    func snapshot() {
        commitAdjust()
        undoStack.append(layers)
        if undoStack.count > 15 { undoStack.removeFirst() }
        canUndo = true
    }

    func undo() {
        adjustBase = nil
        guard let last = undoStack.popLast() else { return }
        layers = last
        canUndo = !undoStack.isEmpty
        if let s = selected, !layers.contains(where: { $0.id == s }) { selected = layers.last?.id }
        rerender()
    }

    func update(_ id: UUID, _ f: (inout PLayer) -> Void) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        var l = layers[i]
        f(&l)
        layers[i] = l
        rerender()
    }

    func hit(_ p: CGPoint) {
        for l in layers.reversed() where l.kind == .raster && l.visible {
            guard let img = l.image else { continue }
            if CGRect(origin: l.origin, size: img.size).contains(p) {
                commitAdjust()
                selected = l.id
                return
            }
        }
    }

    // MARK: Ebenen-Operationen

    func delete(_ id: UUID) {
        snapshot()
        layers.removeAll { $0.id == id }
        if selected == id { selected = layers.last(where: { $0.kind == .raster })?.id }
        rerender()
    }

    func duplicate(_ id: UUID) {
        guard let i = layers.firstIndex(where: { $0.id == id }), layers[i].kind == .raster else { return }
        snapshot()
        var c = layers[i]
        c = PLayer(name: c.name + " Kopie", kind: .raster, image: c.image, origin: c.origin, opacity: c.opacity, blendKey: c.blendKey, visible: c.visible)
        layers.insert(c, at: i + 1)
        selected = c.id
        rerender()
    }

    func moveLayer(_ id: UUID, up: Bool) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i + 1 : i - 1
        guard j >= 0, j < layers.count else { return }
        snapshot()
        layers.swapAt(i, j)
        rerender()
    }

    func addImage(_ img: UIImage, name: String) {
        snapshot()
        var l = PLayer(name: name)
        var im = img
        let maxW = canvas.width, maxH = canvas.height
        if img.size.width > maxW || img.size.height > maxH {
            let r = fitSize(img.size, within: canvas)
            im = Self.resize(img, to: r)
        }
        l.image = im
        l.origin = CGPoint(x: (canvas.width - im.size.width) / 2, y: (canvas.height - im.size.height) / 2)
        layers.append(l)
        selected = l.id
        rerender()
    }

    func addEmptyLayer() {
        snapshot()
        var l = PLayer(name: "Ebene \(layers.count + 1)")
        l.image = Self.solid(size: canvas, color: .clear)
        layers.append(l)
        selected = l.id
        rerender()
    }

    func addText(_ spec: TextSpec) {
        snapshot()
        let img = renderText(spec)
        var l = PLayer(name: "Text")
        l.image = img
        l.origin = CGPoint(x: (canvas.width - img.size.width) / 2, y: (canvas.height - img.size.height) / 2)
        layers.append(l)
        selected = l.id
        rerender()
    }

    static func resize(_ img: UIImage, to size: CGSize) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded())), format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: Pinsel

    func paint(points: [CGPoint], width: CGFloat, color: UIColor, erase: Bool) {
        guard let l = selectedRaster, let img = l.image, let first = points.first else { return }
        snapshot()
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let local = points.map { CGPoint(x: $0.x - l.origin.x, y: $0.y - l.origin.y) }
        let out = UIGraphicsImageRenderer(size: img.size, format: fmt).image { rc in
            img.draw(at: .zero)
            let c = rc.cgContext
            if erase { c.setBlendMode(.clear) }
            c.setStrokeColor(color.cgColor)
            c.setFillColor(color.cgColor)
            c.setLineWidth(width)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            let f = CGPoint(x: first.x - l.origin.x, y: first.y - l.origin.y)
            c.fillEllipse(in: CGRect(x: f.x - width / 2, y: f.y - width / 2, width: width, height: width))
            if local.count > 1 {
                c.move(to: local[0])
                for p in local.dropFirst() { c.addLine(to: p) }
                c.strokePath()
            }
        }
        update(l.id) { $0.image = out }
    }

    // MARK: Transformieren (wird in die Pixel eingerechnet)

    func transform(scale: CGFloat = 1, degrees: CGFloat = 0, flipH: Bool = false, flipV: Bool = false) {
        guard let l = selectedRaster, let img = l.image else { return }
        snapshot()
        var t = CGAffineTransform.identity
        t = t.scaledBy(x: (flipH ? -1 : 1) * scale, y: (flipV ? -1 : 1) * scale)
        t = t.rotated(by: degrees * .pi / 180)
        let bounds = CGRect(origin: .zero, size: img.size)
        let centered = bounds.offsetBy(dx: -img.size.width / 2, dy: -img.size.height / 2).applying(t)
        let newSize = CGSize(width: max(1, centered.width.rounded()), height: max(1, centered.height.rounded()))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let out = UIGraphicsImageRenderer(size: newSize, format: fmt).image { rc in
            let c = rc.cgContext
            c.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            c.concatenate(t)
            img.draw(at: CGPoint(x: -img.size.width / 2, y: -img.size.height / 2))
        }
        let center = CGPoint(x: l.origin.x + img.size.width / 2, y: l.origin.y + img.size.height / 2)
        update(l.id) {
            $0.image = out
            $0.origin = CGPoint(x: center.x - newSize.width / 2, y: center.y - newSize.height / 2)
        }
    }

    func centerLayer() {
        guard let l = selectedRaster, let img = l.image else { return }
        snapshot()
        update(l.id) { $0.origin = CGPoint(x: (canvas.width - img.size.width) / 2, y: (canvas.height - img.size.height) / 2) }
    }

    // MARK: Anpassen (Looks/Korrekturen auf Ebene)

    func adjustLive(adjust: Adjust, look: LookFilter, amount: Double) {
        guard let l = selectedRaster else { return }
        if adjustTarget != l.id || adjustBase == nil {
            snapshot()
            adjustBase = l.image
            adjustTarget = l.id
        }
        guard let base = adjustBase else { return }
        let out = applyLookAndAdjust(base, adjust: adjust, look: look, amount: amount)
        update(l.id) { $0.image = out }
    }

    func commitAdjust() {
        adjustBase = nil
        adjustTarget = nil
    }

    // MARK: Smartcut

    func applyCutout(_ img: UIImage, to id: UUID) {
        snapshot()
        update(id) { $0.image = img }
    }

    // MARK: Export

    func exportImage(transparent: Bool) -> UIImage {
        renderDocument(layers, canvas: canvas, scale: 1, bg: transparent ? nil : .white)
    }

    func psdFile() -> URL? {
        let data = PSDWriter.write(layers: layers, canvas: canvas)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).psd")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}

// MARK: - Bildschirm

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct PSDScreen: View {
    @StateObject private var m = PSDModel()
    @State private var showImporter = false
    @State private var tab: PTab = .move
    @State private var showLayers = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var share: ShareItem?
    @State private var showSmartcut = false
    @State private var showText = false
    @State private var dragStart: CGPoint?
    @State private var pts: [CGPoint] = []
    @State private var brushErase = false
    @State private var brushColor: Color = .black
    @State private var brushSize = 40.0
    @State private var brushOpacity = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !m.hasDoc {
                startView
            } else {
                VStack(spacing: 0) {
                    canvasArea
                    panel
                        .frame(height: 210)
                        .frame(maxWidth: .infinity)
                        .background(Color(white: 0.08))
                    tabBar
                }
            }
            if m.busy {
                ProgressView().scaleEffect(1.4).padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            if let msg = m.message {
                Text(msg).font(.footnote).padding(10).multilineTextAlignment(.center)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
            }
        }
        .navigationTitle("PSD Bearbeitung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if m.hasDoc {
                    Button { showImporter = true } label: { Image(systemName: "folder") }
                    Button { m.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!m.canUndo)
                    Button { showLayers = true } label: { Image(systemName: "square.3.layers.3d") }
                    Menu {
                        Button("Als PNG in Fotos") { saveImage(png: true) }
                        Button("Als JPEG in Fotos") { saveImage(png: false) }
                        Button("Als PSD sichern …") { savePSD() }
                    } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "psd") ?? .data, .data]) { result in
            if case .success(let url) = result { openFile(url) }
        }
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .task(id: m.message) {
            if m.message != nil {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                m.message = nil
            }
        }
        .sheet(isPresented: $showLayers) { PSDLayersSheet(m: m) }
        .sheet(isPresented: $showText) { PSDTextSheet { spec in m.addText(spec) } }
        .sheet(item: $share) { item in ActivityView(url: item.url) }
        .fullScreenCover(isPresented: $showSmartcut) {
            if let l = m.selectedRaster, let img = l.image {
                let id = l.id
                SmartcutView(image: img, startAll: true) { result in
                    if let r = result { m.applyCutout(r, to: id) }
                    showSmartcut = false
                }
            }
        }
    }

    // MARK: Start

    private var startView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.richtext").font(.system(size: 60)).foregroundStyle(.secondary)
            Text("PSD-Dateien ansehen und bearbeiten").font(.headline)
            Button { showImporter = true } label: {
                Label("PSD-Datei öffnen", systemImage: "folder")
                    .bold().padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.blue, in: Capsule()).foregroundStyle(.white)
            }
            Button { m.newDocument(width: 1080, height: 1080) } label: {
                Label("Neues Dokument (1080 × 1080)", systemImage: "plus.square")
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color(white: 0.18), in: Capsule()).foregroundStyle(.white)
            }
            Text("Du findest die Datei in „Dateien“ (iCloud Drive oder Auf meinem iPhone).")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
        }
    }

    // MARK: Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            if let img = m.preview {
                let r = fitRect(m.canvas, in: geo.size)
                let s = r.width / max(m.canvas.width, 1)
                ZStack {
                    PatternView(index: 2, c1: Color(white: 0.2), c2: Color(white: 0.28))
                        .frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                    Image(uiImage: img).resizable()
                        .frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                    if tab == .brush {
                        Path { p in
                            guard let f = pts.first else { return }
                            p.move(to: f)
                            for q in pts.dropFirst() { p.addLine(to: q) }
                            if pts.count == 1 { p.addLine(to: f) }
                        }
                        .stroke(brushErase ? Color.white.opacity(0.5) : brushColor.opacity(brushOpacity),
                                style: StrokeStyle(lineWidth: CGFloat(brushSize) * s, lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false)
                    }
                    Color.clear.contentShape(Rectangle())
                        .gesture(canvasGesture(rect: r, scale: s))
                }
            }
        }
    }

    private func toCanvas(_ p: CGPoint, rect: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(x: (p.x - rect.minX) / scale, y: (p.y - rect.minY) / scale)
    }

    private func canvasGesture(rect: CGRect, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if tab == .brush {
                    if let l = pts.last, hypot(l.x - v.location.x, l.y - v.location.y) < 2 { return }
                    pts.append(v.location)
                } else if tab == .move, let sel = m.selectedRaster, hypot(v.translation.width, v.translation.height) > 4 {
                    if dragStart == nil { m.snapshot(); dragStart = sel.origin }
                    let s = dragStart ?? .zero
                    m.update(sel.id) {
                        $0.origin = CGPoint(x: s.x + v.translation.width / scale, y: s.y + v.translation.height / scale)
                    }
                }
            }
            .onEnded { v in
                if tab == .brush {
                    let cp = pts.map { toCanvas($0, rect: rect, scale: scale) }
                    pts = []
                    if m.selectedRaster == nil { m.message = "Wähle zuerst eine Pixel-Ebene aus."; return }
                    if !cp.isEmpty {
                        m.paint(points: cp, width: CGFloat(brushSize), color: UIColor(brushColor).withAlphaComponent(brushOpacity), erase: brushErase)
                    }
                } else if dragStart != nil {
                    dragStart = nil
                } else if hypot(v.translation.width, v.translation.height) < 6 {
                    m.hit(toCanvas(v.location, rect: rect, scale: scale))
                }
            }
    }

    // MARK: Panels

    private var tabBar: some View {
        HStack {
            ForEach(PTab.allCases, id: \.self) { t in
                Button { tab = t; m.commitAdjust() } label: {
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

    @ViewBuilder private var panel: some View {
        switch tab {
        case .move: PSDLayerPanel(m: m)
        case .brush: PSDBrushPanel(erase: $brushErase, color: $brushColor, size: $brushSize, opacity: $brushOpacity)
        case .adjust: PSDAdjustPanel(m: m)
        case .transform: PSDTransformPanel(m: m)
        case .more: PSDMorePanel(m: m, items: $photoItems, addText: { showText = true }, smartcut: {
            if m.selectedRaster != nil { showSmartcut = true } else { m.message = "Wähle zuerst eine Pixel-Ebene aus." }
        })
        }
    }

    // MARK: Dateien

    private func openFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { m.message = "Datei konnte nicht gelesen werden."; return }
        let name = url.deletingPathExtension().lastPathComponent
        m.busy = true
        Task {
            let result: Result<PSDDocument, PSDError> = await Task.detached(priority: .userInitiated) { () -> Result<PSDDocument, PSDError> in
                do { return .success(try PSDParser.parse(data)) }
                catch let e as PSDError { return .failure(e) }
                catch { return .failure(PSDError(msg: "Unbekannter Fehler beim Lesen.")) }
            }.value
            m.busy = false
            switch result {
            case .success(let doc):
                m.open(doc, name: name)
                m.message = doc.notes.joined(separator: "\n")
            case .failure(let e):
                m.message = e.msg
            }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for it in items {
                if let d = try? await it.loadTransferable(type: Data.self),
                   let img = preparedImage(from: d, maxSide: 4096) { m.addImage(img, name: "Foto") }
            }
            photoItems = []
        }
    }

    private func saveImage(png: Bool) {
        m.busy = true
        let img = m.exportImage(transparent: png)
        PhotoSaver.save(img, png: png) { ok in
            m.busy = false
            m.message = ok ? "In Fotos gesichert" : "Speichern nicht erlaubt"
        }
    }

    private func savePSD() {
        m.busy = true
        if let url = m.psdFile() { share = ShareItem(url: url) } else { m.message = "PSD konnte nicht erstellt werden." }
        m.busy = false
    }
}

// MARK: - Panels

struct PSDLayerPanel: View {
    @ObservedObject var m: PSDModel

    var body: some View {
        VStack(spacing: 10) {
            if let l = m.selectedLayer {
                HStack {
                    Text(l.name).bold().lineLimit(1)
                    Spacer()
                    Button { m.update(l.id) { $0.visible.toggle() } } label: { Image(systemName: l.visible ? "eye" : "eye.slash") }
                    Button { m.moveLayer(l.id, up: true) } label: { Image(systemName: "arrow.up") }
                    Button { m.moveLayer(l.id, up: false) } label: { Image(systemName: "arrow.down") }
                    Button { m.duplicate(l.id) } label: { Image(systemName: "plus.square.on.square") }
                    Button(role: .destructive) { m.delete(l.id) } label: { Image(systemName: "trash") }
                }
                .padding(.horizontal)
                HStack {
                    Text("Deckkraft").font(.footnote).frame(width: 70, alignment: .leading)
                    Slider(value: Binding(get: { l.opacity }, set: { v in m.update(l.id) { $0.opacity = v } }), in: 0...1)
                }
                .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(psdBlendModes, id: \.0) { b in
                            Button { m.update(l.id) { $0.blendKey = b.0 } } label: {
                                Text(b.1).font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(l.blendKey == b.0 ? Color.blue.opacity(0.6) : Color(white: 0.15), in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                Text("Tippe aufs Bild zum Auswählen, ziehe zum Verschieben.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Keine Ebene ausgewählt – tippe aufs Bild oder öffne die Ebenenliste.")
                    .font(.footnote).foregroundStyle(.secondary).padding()
            }
        }
        .padding(.top, 12)
    }
}

struct PSDBrushPanel: View {
    @Binding var erase: Bool
    @Binding var color: Color
    @Binding var size: Double
    @Binding var opacity: Double

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $erase) {
                Text("Pinsel").tag(false)
                Text("Radierer").tag(true)
            }
            .pickerStyle(.segmented).padding(.horizontal)
            HStack { Text("Größe").font(.footnote).frame(width: 70, alignment: .leading); Slider(value: $size, in: 2...300) }
                .padding(.horizontal)
            HStack { Text("Deckkraft").font(.footnote).frame(width: 70, alignment: .leading); Slider(value: $opacity, in: 0.05...1) }
                .padding(.horizontal)
            ColorPicker("Farbe", selection: $color).font(.footnote).padding(.horizontal)
            Text("Malt auf der gewählten Pixel-Ebene (nur innerhalb ihrer Fläche). Neue leere Ebene unter „Mehr“.")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal)
        }
        .padding(.top, 12)
    }
}

struct PSDAdjustPanel: View {
    @ObservedObject var m: PSDModel
    @State private var adjust = Adjust()
    @State private var look: LookFilter = .none
    @State private var amount = 1.0
    @State private var sel = adjSpecs[0].id

    var body: some View {
        let spec = adjSpecs.first { $0.id == sel } ?? adjSpecs[0]
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LookFilter.allCases) { lf in
                        Button { look = lf; push() } label: {
                            Text(lf.title).font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(look == lf ? Color.blue.opacity(0.6) : Color(white: 0.15), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(adjSpecs) { s in
                        Button { sel = s.id } label: {
                            Text(s.name).font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(sel == s.id ? Color.indigo.opacity(0.7) : Color(white: 0.15), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                Slider(value: Binding(get: { adjust[keyPath: spec.keyPath] }, set: { adjust[keyPath: spec.keyPath] = $0; push() }), in: spec.range)
                Text("\(Int((adjust[keyPath: spec.keyPath] * 100).rounded()))").monospacedDigit().frame(width: 44)
            }
            .padding(.horizontal)
            HStack {
                Text("Look-Stärke").font(.footnote)
                Slider(value: $amount, in: 0...1) { editing in if !editing { push() } }
            }
            .padding(.horizontal)
            Button("Anwenden / Neu beginnen") { m.commitAdjust(); adjust = Adjust(); look = .none; amount = 1 }
                .font(.footnote)
        }
        .padding(.top, 10)
        .onChange(of: m.selected) { _, _ in adjust = Adjust(); look = .none; amount = 1 }
    }

    private func push() { m.adjustLive(adjust: adjust, look: look, amount: amount) }
}

struct PSDTransformPanel: View {
    @ObservedObject var m: PSDModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                btn("90° ↻", "rotate.right") { m.transform(degrees: 90) }
                btn("15° ↻", "arrow.clockwise") { m.transform(degrees: 15) }
                btn("15° ↺", "arrow.counterclockwise") { m.transform(degrees: -15) }
            }
            HStack(spacing: 10) {
                btn("Spiegeln ↔", "arrow.left.and.right") { m.transform(flipH: true) }
                btn("Spiegeln ↕", "arrow.up.and.down") { m.transform(flipV: true) }
                btn("Zentrieren", "scope") { m.centerLayer() }
            }
            HStack(spacing: 10) {
                btn("50 %", "minus.magnifyingglass") { m.transform(scale: 0.5) }
                btn("90 %", "minus") { m.transform(scale: 0.9) }
                btn("110 %", "plus") { m.transform(scale: 1.1) }
                btn("200 %", "plus.magnifyingglass") { m.transform(scale: 2) }
            }
            Text("Transformationen werden direkt in die Ebene eingerechnet (Rückgängig möglich).")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.top, 14)
    }

    private func btn(_ t: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(t, systemImage: icon).font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 10)
                .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
        }
    }
}

struct PSDMorePanel: View {
    @ObservedObject var m: PSDModel
    @Binding var items: [PhotosPickerItem]
    let addText: () -> Void
    let smartcut: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $items, maxSelectionCount: 5, matching: .images) {
                    tile("Foto", "photo.badge.plus")
                }
                Button(action: addText) { tile("Text", "textformat") }
                Button { m.addEmptyLayer() } label: { tile("Leere Ebene", "square.dashed") }
                Button(action: smartcut) { tile("Smartcut", "wand.and.stars") }
            }
            .padding(.horizontal)
            .padding(.top, 20)
        }
    }

    private func tile(_ t: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.15))
                Image(systemName: icon).font(.title2)
            }
            .frame(width: 78, height: 78)
            Text(t).font(.caption2)
        }
        .foregroundStyle(.white)
    }
}

struct PSDTextSheet: View {
    let onAdd: (TextSpec) -> Void
    @State private var spec = TextSpec()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Text", text: $spec.text)
                Picker("Schrift", selection: $spec.fontIndex) {
                    Text("Standard").tag(0); Text("Rund").tag(1); Text("Serif").tag(2); Text("Mono").tag(3)
                }
                .pickerStyle(.segmented)
                Slider(value: $spec.size, in: 20...400) { Text("Größe") }
                ColorPicker("Farbe", selection: $spec.color)
                Toggle("Fett", isOn: $spec.bold)
                Toggle("Kontur", isOn: $spec.outline)
            }
            .navigationTitle("Text")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Hinzufügen") { onAdd(spec); dismiss() }.bold() }
            }
        }
        .presentationDetents([.medium])
    }
}

struct PSDLayersSheet: View {
    @ObservedObject var m: PSDModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(m.layers.reversed())) { l in
                    HStack(spacing: 12) {
                        icon(l)
                        Text(l.name)
                            .foregroundStyle(m.selected == l.id ? Color.blue : (l.kind == .groupEnd ? Color.secondary : Color.primary))
                            .font(l.kind == .groupStart ? .body.bold() : .body)
                        Spacer()
                        if l.kind != .groupEnd {
                            Button { m.update(l.id) { $0.visible.toggle() } } label: {
                                Image(systemName: l.visible ? "eye" : "eye.slash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if l.kind == .raster { m.selected = l.id } }
                    .swipeActions {
                        Button(role: .destructive) { m.delete(l.id) } label: { Label("Löschen", systemImage: "trash") }
                    }
                }
                .onMove { from, to in
                    m.snapshot()
                    var rev = Array(m.layers.reversed())
                    rev.move(fromOffsets: from, toOffset: to)
                    m.layers = Array(rev.reversed())
                    m.rerender()
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

    @ViewBuilder private func icon(_ l: PLayer) -> some View {
        switch l.kind {
        case .raster:
            if let img = l.image {
                Image(uiImage: img).resizable().scaledToFit().frame(width: 44, height: 44)
                    .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Color.gray.frame(width: 44, height: 44)
            }
        case .groupStart:
            Image(systemName: "folder").frame(width: 44, height: 44)
        case .groupEnd:
            Image(systemName: "arrow.turn.down.right").frame(width: 44, height: 44).foregroundStyle(.secondary)
        }
    }
}
