import SwiftUI
import PhotosUI
import Photos
import Vision
import CoreImage

// MARK: - App

@main
struct FotoStudioApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Wird bei jeder Lieferung hochgezählt, damit man sieht, welche Fassung installiert ist.
let appBuildTag = "Build 9"

// MARK: - Startseite (Aufbau wie Photoshop Express)

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.10), .black],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                RadialGradient(colors: [Color.blue.opacity(0.35), .clear], center: .topTrailing,
                               startRadius: 10, endRadius: 420).ignoresSafeArea()
                RadialGradient(colors: [Color.purple.opacity(0.28), .clear], center: .bottomLeading,
                               startRadius: 10, endRadius: 420).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        Text("Was möchtest du tun?")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.top, 8)

                        NavigationLink {
                            EditorScreen()
                        } label: {
                            HomeTile(title: "Bearb. & Retusche",
                                     subtitle: "Korrekturen, Looks, Zuschneiden, Retusche, Freistellen",
                                     icon: "slider.horizontal.3",
                                     colors: [Color(red: 0.25, green: 0.35, blue: 0.95), Color(red: 0.62, green: 0.25, blue: 0.85)])
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            CombineScreen()
                        } label: {
                            HomeTile(title: "Fotos kombinieren",
                                     subtitle: "Collagen, Ebenen, Überblenden, Freistellen",
                                     icon: "square.on.square",
                                     colors: [Color(red: 0.98, green: 0.55, blue: 0.15), Color(red: 0.92, green: 0.25, blue: 0.45)])
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            PSDScreen()
                        } label: {
                            HomeTile(title: "PSD Bearbeitung",
                                     subtitle: "PSD-Dateien öffnen, Ebenen bearbeiten, als PSD/PNG/JPEG sichern",
                                     icon: "square.3.layers.3d",
                                     colors: [Color(red: 0.08, green: 0.68, blue: 0.62), Color(red: 0.15, green: 0.78, blue: 0.42)])
                        }
                        .buttonStyle(.plain)

                        Text("Version \(appBuildTag)")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .shadow(color: .cyan.opacity(0.5), radius: 12)
                Image(systemName: "camera.aperture")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("Foto").foregroundStyle(.white)
                    Text("Studio").foregroundStyle(Color.cyan)
                }
                .font(.system(size: 36, weight: .bold))
                Text("Professionelle Bildbearbeitung")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
        }
        .padding(.top, 16)
    }
}

struct HomeTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let colors: [Color]

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 60, height: 60)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.footnote).opacity(0.92)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right").opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        .shadow(color: colors[0].opacity(0.45), radius: 14, y: 6)
    }
}

// MARK: - Hilfsfunktionen

/// Bild laden, Ausrichtung korrigieren und auf maximale Kantenlänge verkleinern.
func preparedImage(from data: Data, maxSide: CGFloat) -> UIImage? {
    guard let src = UIImage(data: data) else { return nil }
    let longest = max(src.size.width, src.size.height)
    guard longest > 0 else { return nil }
    let s = min(1, maxSide / longest)
    let newSize = CGSize(width: (src.size.width * s).rounded(), height: (src.size.height * s).rounded())
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    fmt.opaque = false
    return UIGraphicsImageRenderer(size: newSize, format: fmt).image { _ in
        src.draw(in: CGRect(origin: .zero, size: newSize))
    }
}

/// Größtes Rechteck mit dem Seitenverhältnis von `size`, das mittig in `container` passt.
func fitRect(_ size: CGSize, in container: CGSize) -> CGRect {
    guard size.width > 0, size.height > 0 else { return .zero }
    let s = min(container.width / size.width, container.height / size.height)
    let w = size.width * s
    let h = size.height * s
    return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
}

func fitSize(_ size: CGSize, within container: CGSize) -> CGSize {
    fitRect(size, in: container).size
}

enum PhotoSaver {
    static func save(_ image: UIImage, png: Bool, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let data = png ? image.pngData() : image.jpegData(compressionQuality: 0.95)
            guard let d = data else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: d, options: nil)
            }) { ok, _ in
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }
}

/// Motiv freistellen (Vordergrund-Maske von Apple Vision, nur auf echtem iPhone).
enum Cutout {
    static func run(_ image: UIImage) async -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
                guard let obs = request.results?.first else { return nil }
                let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances,
                                                         from: handler,
                                                         croppedToInstancesExtent: false)
                let ci = CIImage(cvPixelBuffer: buffer)
                let ctx = CIContext()
                guard let out = ctx.createCGImage(ci, from: ci.extent) else { return nil }
                return UIImage(cgImage: out)
            } catch {
                return nil
            }
        }.value
    }
}
