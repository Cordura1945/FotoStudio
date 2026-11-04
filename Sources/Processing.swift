import SwiftUI
import CoreImage
import UIKit

let sharedCI = CIContext()

// MARK: - Core-Image-Helfer

func ci(_ name: String, _ img: CIImage, _ p: [String: Any] = [:]) -> CIImage {
    guard let f = CIFilter(name: name) else { return img }
    f.setValue(img, forKey: kCIInputImageKey)
    for (k, v) in p { f.setValue(v, forKey: k) }
    return f.outputImage ?? img
}

/// t = 0 -> a, t = 1 -> b
func mix(_ a: CIImage, _ b: CIImage, _ t: Double) -> CIImage {
    if t <= 0 { return a }
    if t >= 1 { return b }
    return ci("CIDissolveTransition", a, ["inputTargetImage": b, "inputTime": t])
}

func colorMatrix(_ img: CIImage, r: CGFloat, g: CGFloat, b: CGFloat) -> CIImage {
    ci("CIColorMatrix", img, [
        "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
    ])
}

func blurred(_ img: CIImage, _ radius: Double) -> CIImage {
    let e = img.extent
    return ci("CIGaussianBlur", img.clampedToExtent(), ["inputRadius": radius]).cropped(to: e)
}

func toneCurve(_ img: CIImage, _ pts: [(CGFloat, CGFloat)]) -> CIImage {
    var p: [String: Any] = [:]
    for (i, pt) in pts.enumerated() { p["inputPoint\(i)"] = CIVector(x: pt.0, y: pt.1) }
    return ci("CIToneCurve", img, p)
}

// MARK: - Korrekturen

struct Adjust: Equatable {
    var exposure = 0.0
    var contrast = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var brightness = 0.0
    var saturation = 0.0
    var vibrance = 0.0
    var temperature = 0.0
    var tint = 0.0
    var clarity = 0.0
    var sharpen = 0.0
    var denoise = 0.0
    var blur = 0.0
    var vignette = 0.0
    var grain = 0.0
}

struct AdjSpec: Identifiable {
    let id: String
    let name: String
    let icon: String
    let keyPath: WritableKeyPath<Adjust, Double>
    let range: ClosedRange<Double>
}

let adjSpecs: [AdjSpec] = [
    AdjSpec(id: "exposure", name: "Belichtung", icon: "sun.max", keyPath: \.exposure, range: -1...1),
    AdjSpec(id: "contrast", name: "Kontrast", icon: "circle.lefthalf.filled", keyPath: \.contrast, range: -1...1),
    AdjSpec(id: "highlights", name: "Lichter", icon: "sun.haze", keyPath: \.highlights, range: -1...1),
    AdjSpec(id: "shadows", name: "Tiefen", icon: "moon.fill", keyPath: \.shadows, range: -1...1),
    AdjSpec(id: "brightness", name: "Helligkeit", icon: "sun.min", keyPath: \.brightness, range: -1...1),
    AdjSpec(id: "saturation", name: "Sättigung", icon: "drop.fill", keyPath: \.saturation, range: -1...1),
    AdjSpec(id: "vibrance", name: "Dynamik", icon: "sparkles", keyPath: \.vibrance, range: -1...1),
    AdjSpec(id: "temperature", name: "Temperatur", icon: "thermometer.medium", keyPath: \.temperature, range: -1...1),
    AdjSpec(id: "tint", name: "Tönung", icon: "paintbrush", keyPath: \.tint, range: -1...1),
    AdjSpec(id: "clarity", name: "Klarheit", icon: "triangle", keyPath: \.clarity, range: 0...1),
    AdjSpec(id: "sharpen", name: "Schärfen", icon: "scope", keyPath: \.sharpen, range: 0...1),
    AdjSpec(id: "denoise", name: "Rauschen", icon: "waveform", keyPath: \.denoise, range: 0...1),
    AdjSpec(id: "blur", name: "Weichzeichnen", icon: "circle.dotted", keyPath: \.blur, range: 0...1),
    AdjSpec(id: "vignette", name: "Vignette", icon: "circle.dashed", keyPath: \.vignette, range: 0...1),
    AdjSpec(id: "grain", name: "Körnung", icon: "circle.grid.3x3", keyPath: \.grain, range: 0...1)
]

// MARK: - Looks

enum LookFilter: String, CaseIterable, Identifiable {
    case none, chrome, fade, instant, mono, noir, process, tonal, transfer, sepia
    case warm, cool, vintage, dramatic, vivid, matte, dream

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Original"
        case .chrome: return "Chrom"
        case .fade: return "Verblasst"
        case .instant: return "Sofortbild"
        case .mono: return "Mono"
        case .noir: return "Noir"
        case .process: return "Prozess"
        case .tonal: return "Tonal"
        case .transfer: return "Transfer"
        case .sepia: return "Sepia"
        case .warm: return "Warm"
        case .cool: return "Kühl"
        case .vintage: return "Vintage"
        case .dramatic: return "Dramatisch"
        case .vivid: return "Lebendig"
        case .matte: return "Matt"
        case .dream: return "Traum"
        }
    }

    func apply(_ i: CIImage) -> CIImage {
        switch self {
        case .none: return i
        case .chrome: return ci("CIPhotoEffectChrome", i)
        case .fade: return ci("CIPhotoEffectFade", i)
        case .instant: return ci("CIPhotoEffectInstant", i)
        case .mono: return ci("CIPhotoEffectMono", i)
        case .noir: return ci("CIPhotoEffectNoir", i)
        case .process: return ci("CIPhotoEffectProcess", i)
        case .tonal: return ci("CIPhotoEffectTonal", i)
        case .transfer: return ci("CIPhotoEffectTransfer", i)
        case .sepia: return ci("CISepiaTone", i, ["inputIntensity": 1.0])
        case .warm:
            return ci("CIColorControls", colorMatrix(i, r: 1.12, g: 1.0, b: 0.88), ["inputSaturation": 1.1])
        case .cool:
            return colorMatrix(i, r: 0.9, g: 1.0, b: 1.12)
        case .vintage:
            let s = ci("CISepiaTone", i, ["inputIntensity": 0.55])
            let c = ci("CIColorControls", s, ["inputContrast": 0.92, "inputBrightness": 0.03])
            return ci("CIVignette", c, ["inputIntensity": 1.0, "inputRadius": 1.5])
        case .dramatic:
            let c = ci("CIColorControls", i, ["inputContrast": 1.35, "inputSaturation": 0.7])
            return ci("CIVignette", c, ["inputIntensity": 1.2, "inputRadius": 1.6])
        case .vivid:
            let c = ci("CIColorControls", i, ["inputContrast": 1.1, "inputSaturation": 1.35])
            return ci("CIVibrance", c, ["inputAmount": 0.5])
        case .matte:
            let t = toneCurve(i, [(0, 0.08), (0.25, 0.27), (0.5, 0.5), (0.75, 0.74), (1, 0.94)])
            return ci("CIColorControls", t, ["inputSaturation": 0.9])
        case .dream:
            return ci("CIBloom", i, ["inputRadius": 12.0, "inputIntensity": 0.9]).cropped(to: i.extent)
        }
    }
}

// MARK: - Gesamte Pipeline

func processImage(_ input: CIImage, adjust a: Adjust, look: LookFilter, lookAmount: Double) -> CIImage {
    let e = input.extent
    var i = input

    if a.exposure != 0 { i = ci("CIExposureAdjust", i, ["inputEV": a.exposure * 2.0]) }

    if a.highlights != 0 || a.shadows != 0 {
        i = toneCurve(i, [
            (0, 0),
            (0.25, CGFloat(0.25 + a.shadows * 0.12)),
            (0.5, 0.5),
            (0.75, CGFloat(0.75 + a.highlights * 0.12)),
            (1, 1)
        ])
    }

    if a.contrast != 0 || a.brightness != 0 || a.saturation != 0 {
        i = ci("CIColorControls", i, [
            "inputContrast": 1 + a.contrast * 0.5,
            "inputBrightness": a.brightness * 0.25,
            "inputSaturation": 1 + a.saturation
        ])
    }

    if a.vibrance != 0 { i = ci("CIVibrance", i, ["inputAmount": a.vibrance]) }

    if a.temperature != 0 || a.tint != 0 {
        i = colorMatrix(i,
                        r: CGFloat(1 + a.temperature * 0.2),
                        g: CGFloat(1 - a.tint * 0.15),
                        b: CGFloat(1 - a.temperature * 0.2))
    }

    if a.clarity > 0 { i = ci("CIUnsharpMask", i, ["inputRadius": 18.0, "inputIntensity": a.clarity]) }
    if a.sharpen > 0 { i = ci("CISharpenLuminance", i, ["inputSharpness": a.sharpen * 2.0, "inputRadius": 1.7]) }
    if a.denoise > 0 { i = ci("CINoiseReduction", i, ["inputNoiseLevel": a.denoise * 0.05, "inputSharpness": 0.4]) }
    if a.blur > 0 { i = blurred(i, a.blur * 18) }
    if a.vignette > 0 { i = ci("CIVignette", i, ["inputIntensity": a.vignette * 1.5, "inputRadius": 1.2]) }

    if a.grain > 0, let n = CIFilter(name: "CIRandomGenerator")?.outputImage {
        let g = ci("CIColorControls", n.cropped(to: e), ["inputSaturation": 0.0])
        let soft = ci("CISoftLightBlendMode", g, ["inputBackgroundImage": i]).cropped(to: e)
        i = mix(i, soft, min(1, a.grain * 0.8))
    }

    if look != .none { i = mix(i, look.apply(i).cropped(to: e), lookAmount) }

    // Transparenz des Originals erhalten
    return i.cropped(to: e).applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: input])
}

/// Looks/Änderungen auf ein UIImage anwenden (z. B. für Ebenen).
func applyLookAndAdjust(_ ui: UIImage, adjust: Adjust, look: LookFilter, amount: Double) -> UIImage {
    if adjust == Adjust() && look == .none { return ui }
    guard let cg = ui.cgImage else { return ui }
    let src = CIImage(cgImage: cg)
    let out = processImage(src, adjust: adjust, look: look, lookAmount: amount)
    guard let res = sharedCI.createCGImage(out, from: src.extent) else { return ui }
    return UIImage(cgImage: res)
}
