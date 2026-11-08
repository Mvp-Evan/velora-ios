import SwiftUI
import UIKit
import AVFoundation

/// In-app camera only for seller 补图 (DES-v1.3-02-04 ITEM-06). Watermark on preview + JPEG.
struct SupplementCameraView: View {
    let listingId: Int64
    let shooterId: Int64
    var onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var permissionDenied = false

    private var watermarkText: String {
        ListingWatermark.line(
            shortCode: ListingWatermark.shortCode(listingId: listingId),
            date: Date(),
            shooterIdSuffix: ListingWatermark.idSuffix(shooterId)
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if permissionDenied {
                VStack(spacing: 16) {
                    Text("需要相机权限才能补图").font(.vHeadline).foregroundStyle(.white)
                    Text("补图必须使用 App 内相机，不可从相册选择").font(.vCaption).foregroundStyle(.white.opacity(0.7))
                    Button("关闭") { dismiss() }.foregroundStyle(Color.vPrimary)
                }
            } else {
                CameraPreviewRepresentable(
                    watermarkText: watermarkText,
                    onCapture: { data in
                        onCapture(data)
                        dismiss()
                    },
                    onCancel: { dismiss() },
                    onDenied: { permissionDenied = true }
                )
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                        Spacer()
                    }
                    .padding()
                    Spacer()
                    Text("请拍清晰，水印不可裁")
                        .font(.vCaptionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 24)
                }
            }
        }
        .statusBarHidden(true)
    }
}

// MARK: - UIKit camera

private struct CameraPreviewRepresentable: UIViewControllerRepresentable {
    let watermarkText: String
    let onCapture: (Data) -> Void
    let onCancel: () -> Void
    let onDenied: () -> Void

    func makeUIViewController(context: Context) -> SupplementCameraController {
        let vc = SupplementCameraController()
        vc.watermarkText = watermarkText
        vc.onCapture = onCapture
        vc.onCancel = onCancel
        vc.onDenied = onDenied
        return vc
    }

    func updateUIViewController(_ uiViewController: SupplementCameraController, context: Context) {
        uiViewController.watermarkText = watermarkText
    }
}

final class SupplementCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    var watermarkText: String = ""
    var onCapture: ((Data) -> Void)?
    var onCancel: (() -> Void)?
    var onDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var preview: AVCaptureVideoPreviewLayer?
    private let watermarkLabel = UILabel()
    private let shutter = UIButton(type: .system)
    private var configured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAndConfigure()
        layoutChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    private func requestAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async {
                    if ok { self?.configureSession() } else { self?.onDenied?() }
                }
            }
        default:
            onDenied?()
        }
    }

    private func configureSession() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(output)
        else {
            onDenied?()
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        preview = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    private func layoutChrome() {
        watermarkLabel.text = watermarkText
        watermarkLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        watermarkLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        watermarkLabel.numberOfLines = 2
        watermarkLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(watermarkLabel)

        shutter.setImage(UIImage(systemName: "circle.fill"), for: .normal)
        shutter.tintColor = .white
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        view.addSubview(shutter)

        NSLayoutConstraint.activate([
            watermarkLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            watermarkLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            watermarkLabel.bottomAnchor.constraint(equalTo: shutter.topAnchor, constant: -20),
            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            shutter.widthAnchor.constraint(equalToConstant: 72),
            shutter.heightAnchor.constraint(equalToConstant: 72),
        ])
    }

    @objc private func takePhoto() {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            return
        }
        let stamped = Self.stamp(image: image, text: watermarkText)
        let jpeg = stamped.jpegData(compressionQuality: 0.85) ?? data
        onCapture?(jpeg)
    }

    private static func stamp(image: UIImage, text: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(at: .zero)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: max(image.size.width * 0.028, 14), weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: paragraph,
            ]
            let margin = image.size.width * 0.04
            let rect = CGRect(
                x: margin,
                y: image.size.height - margin - 40,
                width: image.size.width - margin * 2,
                height: 40
            )
            // Scrim for readability
            UIColor.black.withAlphaComponent(0.35).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: -6, dy: -4), cornerRadius: 6).fill()
            (text as NSString).draw(in: rect, withAttributes: attrs)
        }
    }
}
