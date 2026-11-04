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

// MARK: - Startseite (Aufbau wie Photoshop Express)

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Was möchtest du tun?")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        EditorScreen()
                    } label: {
                        HomeTile(title: "Bearb. & Retusche",
                                 subtitle: "Korrekturen, Looks, Zuschneiden, Retusche, Freistellen",
                                 icon: "slider.horizontal.3",
                                 colors: [.blue, .purple])
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        CombineScreen()
                    } label: {
                        HomeTile(title: "Fotos kombinieren",
                                 subtitle: "Collagen, Ebenen, Überblenden, Freistellen",
                                 icon: "square.on.square",
                                 colors: [.orange, .pink])
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        PSDScreen()
                    } label: {
                        HomeTile(title: "PSD Bearbeitung",
                                 subtitle: "PSD-Dateien öffnen, Ebenen bearbeiten, als PSD/PNG/JPEG sichern",
                                 icon: "square.3.layers.3d",
                                 colors: [.teal, .green])
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle("FotoStudio")
        }
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
                .font(.system(size: 36, weight: .semibold))
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.footnote).opacity(0.9)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right").opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
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
