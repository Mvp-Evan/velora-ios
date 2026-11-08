import SwiftUI
import UIKit
import AVFoundation

/// AVCapture photo — in-app only, no PHPicker (DES-v1.3-09-01 §5.2 / §5.6).
struct EvidencePhotoCameraView: View {
    let watermarkText: String
    let slotLabel: String
    var onCapture: (Data) -> Void
    var onCancel: () -> Void

    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if permissionDenied {
                VStack(spacing: 16) {
                    Text(EvidenceCopy.cameraDenied)
                        .font(.vHeadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("关闭") { onCancel() }.foregroundStyle(Color.vPrimary)
                }
            } else {
                EvidencePhotoCameraRepresentable(
                    watermarkText: watermarkText,
                    onCapture: onCapture,
                    onCancel: onCancel,
                    onDenied: { permissionDenied = true }
                )
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                        Spacer()
                        Text(slotLabel)
                            .font(.vCaptionMedium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.45), in: Capsule())
                        Spacer()
                        Color.clear.frame(width: 36, height: 36)
                    }
                    .padding()
                    Spacer()
                    Text(EvidenceCopy.watermarkPreviewHint)
                        .font(.vCaption)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.bottom, 12)
                }
            }
        }
        .statusBarHidden(true)
    }
}

private struct EvidencePhotoCameraRepresentable: UIViewControllerRepresentable {
    let watermarkText: String
    let onCapture: (Data) -> Void
    let onCancel: () -> Void
    let onDenied: () -> Void

    func makeUIViewController(context: Context) -> EvidencePhotoCameraController {
        let vc = EvidencePhotoCameraController()
        vc.watermarkText = watermarkText
        vc.onCapture = onCapture
        vc.onCancel = onCancel
        vc.onDenied = onDenied
        return vc
    }

    func updateUIViewController(_ uiViewController: EvidencePhotoCameraController, context: Context) {
        uiViewController.watermarkText = watermarkText
    }
}

final class EvidencePhotoCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
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
        watermarkLabel.textColor = UIColor.white.withAlphaComponent(CGFloat(EvidenceConfigDefaults.watermarkOpacity))
        watermarkLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        watermarkLabel.numberOfLines = 1
        watermarkLabel.lineBreakMode = .byTruncatingMiddle
        watermarkLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(watermarkLabel)

        shutter.setImage(UIImage(systemName: "circle.fill"), for: .normal)
        shutter.tintColor = .white
        shutter.accessibilityLabel = "快门"
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        view.addSubview(shutter)

        let margin = EvidenceConfigDefaults.watermarkMarginPx
        NSLayoutConstraint.activate([
            watermarkLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -margin),
            watermarkLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: margin),
            watermarkLabel.bottomAnchor.constraint(equalTo: shutter.topAnchor, constant: -16),
            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            shutter.widthAnchor.constraint(equalToConstant: 72),
            shutter.heightAnchor.constraint(equalToConstant: 72),
        ])
    }

    @objc private func takePhoto() {
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        let stamped = Self.stamp(image: image, text: watermarkText)
        let jpeg = stamped.jpegData(compressionQuality: EvidenceConfigDefaults.jpegQuality) ?? data
        onCapture?(jpeg)
    }

    /// Preview watermark (server re-burns authoritative text). Bottom-right, 85% opacity.
    private static func stamp(image: UIImage, text: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(at: .zero)
            let fontSize = max(image.size.width * 0.022, EvidenceConfigDefaults.watermarkFontPt)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(CGFloat(EvidenceConfigDefaults.watermarkOpacity)),
                .strokeColor: UIColor.black.withAlphaComponent(0.55),
                .strokeWidth: -EvidenceConfigDefaults.watermarkStrokePx,
            ]
            let ns = text as NSString
            let size = ns.size(withAttributes: attrs)
            let margin = EvidenceConfigDefaults.watermarkMarginPx
            let origin = CGPoint(
                x: image.size.width - size.width - margin,
                y: image.size.height - size.height - margin
            )
            ns.draw(at: origin, withAttributes: attrs)
        }
    }
}

// MARK: - One-shot video (no pause / trim)

/// One continuous take; mid-exit requires re-record (design §5.3).
struct EvidenceVideoRecorderView: View {
    let watermarkText: String
    let title: String
    var onFinished: (URL, Int64) -> Void
    var onCancel: () -> Void
    var onInterrupted: () -> Void

    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if permissionDenied {
                VStack(spacing: 16) {
                    Text(EvidenceCopy.cameraDenied)
                        .font(.vHeadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("关闭") { onCancel() }.foregroundStyle(Color.vPrimary)
                }
            } else {
                EvidenceVideoRecorderRepresentable(
                    watermarkText: watermarkText,
                    onFinished: onFinished,
                    onCancel: onCancel,
                    onInterrupted: onInterrupted,
                    onDenied: { permissionDenied = true }
                )
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                        Spacer()
                        Text(title)
                            .font(.vCaptionMedium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.45), in: Capsule())
                        Spacer()
                        Color.clear.frame(width: 36, height: 36)
                    }
                    .padding()
                    Spacer()
                }
            }
        }
        .statusBarHidden(true)
    }
}

private struct EvidenceVideoRecorderRepresentable: UIViewControllerRepresentable {
    let watermarkText: String
    let onFinished: (URL, Int64) -> Void
    let onCancel: () -> Void
    let onInterrupted: () -> Void
    let onDenied: () -> Void

    func makeUIViewController(context: Context) -> EvidenceVideoRecorderController {
        let vc = EvidenceVideoRecorderController()
        vc.watermarkText = watermarkText
        vc.onFinished = onFinished
        vc.onCancel = onCancel
        vc.onInterrupted = onInterrupted
        vc.onDenied = onDenied
        return vc
    }

    func updateUIViewController(_ uiViewController: EvidenceVideoRecorderController, context: Context) {
        uiViewController.watermarkText = watermarkText
    }
}

final class EvidenceVideoRecorderController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    var watermarkText: String = ""
    var onFinished: ((URL, Int64) -> Void)?
    var onCancel: (() -> Void)?
    var onInterrupted: (() -> Void)?
    var onDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var preview: AVCaptureVideoPreviewLayer?
    private let recordButton = UIButton(type: .system)
    private let timerLabel = UILabel()
    private let watermarkLabel = UILabel()
    private var configured = false
    private var recording = false
    private var startedAt: Date?
    private var timer: Timer?
    private var maxTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        requestAndConfigure()
        layoutChrome()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        maxTimer?.invalidate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
        maxTimer?.invalidate()
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
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
        session.sessionPreset = .high
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(movieOutput)
        else {
            onDenied?()
            return
        }
        session.addInput(input)
        // Video-only — avoid NSMicrophoneUsageDescription for evidence fingerprint path.
        session.addOutput(movieOutput)
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
        timerLabel.text = "00:00"
        timerLabel.textColor = .white
        timerLabel.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timerLabel)

        watermarkLabel.text = watermarkText
        watermarkLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        watermarkLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        watermarkLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(watermarkLabel)

        recordButton.setImage(UIImage(systemName: "record.circle"), for: .normal)
        recordButton.tintColor = .systemRed
        recordButton.accessibilityLabel = "开始录像"
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.addTarget(self, action: #selector(toggleRecord), for: .touchUpInside)
        view.addSubview(recordButton)

        NSLayoutConstraint.activate([
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            watermarkLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            watermarkLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -16),
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            recordButton.widthAnchor.constraint(equalToConstant: 80),
            recordButton.heightAnchor.constraint(equalToConstant: 80),
        ])
    }

    @objc private func toggleRecord() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !movieOutput.isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("evidence-\(UUID().uuidString).mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        recording = true
        startedAt = Date()
        recordButton.setImage(UIImage(systemName: "stop.circle.fill"), for: .normal)
        recordButton.accessibilityLabel = "停止录像"
        UIAccessibility.post(notification: .announcement, argument: "正在录像")
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let started = self.startedAt else { return }
            let sec = Int(Date().timeIntervalSince(started))
            self.timerLabel.text = String(format: "%02d:%02d", sec / 60, sec % 60)
        }
        let maxSec = TimeInterval(EvidenceConfigDefaults.videoMaxDurationMs) / 1000
        maxTimer = Timer.scheduledTimer(withTimeInterval: maxSec, repeats: false) { [weak self] _ in
            self?.stopRecording()
        }
    }

    private func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    @objc private func sessionInterrupted() {
        if recording {
            recording = false
            timer?.invalidate()
            maxTimer?.invalidate()
            onInterrupted?()
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        timer?.invalidate()
        maxTimer?.invalidate()
        recording = false
        if error != nil {
            onInterrupted?()
            return
        }
        let ms: Int64
        if let started = startedAt {
            ms = Int64(Date().timeIntervalSince(started) * 1000)
        } else {
            ms = 0
        }
        onFinished?(outputFileURL, ms)
    }
}
