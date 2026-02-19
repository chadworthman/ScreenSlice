import Foundation
import ScreenCaptureKit
import CoreMedia

@MainActor
class ScreenCaptureManager: NSObject, ObservableObject {
    @Published var isCapturing = false
    @Published var isAudioEnabled = false

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var currentDisplay: SCDisplay?
    private var captureRect: CGRect = .zero
    private var currentFPS: Int = 30

    private let videoQueue = DispatchQueue(label: "com.screenslice.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.screenslice.audio", qos: .userInteractive)

    var onFrameReceived: (@Sendable (IOSurface) -> Void)?

    override init() {
        super.init()
    }

    // MARK: - Public API

    /// Starts capturing the specified rectangle of the main display.
    func startCapture(rect: CGRect, fps: Int = 30, audio: Bool = false) async throws {
        guard !isCapturing else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // Find the display that contains the capture rect
        let targetDisplay = content.displays.first(where: { display in
            let displayFrame = CGRect(x: Int(display.frame.origin.x),
                                       y: Int(display.frame.origin.y),
                                       width: display.width,
                                       height: display.height)
            return displayFrame.intersects(rect)
        }) ?? content.displays.first

        guard let display = targetDisplay else {
            throw CaptureError.noDisplayFound
        }
        currentDisplay = display
        currentFPS = fps
        isAudioEnabled = audio

        // Convert from NSScreen (bottom-left origin) to CG (top-left origin) coordinates
        // and make relative to the display's frame
        let displayFrame = display.frame
        let relativeX = rect.origin.x - displayFrame.origin.x
        let relativeY = displayFrame.height - (rect.origin.y - displayFrame.origin.y) - rect.height
        let cgRect = CGRect(x: relativeX, y: relativeY, width: rect.width, height: rect.height)
        captureRect = cgRect

        ssLog("Display: \(display.width)x\(display.height) at \(displayFrame.origin)")
        ssLog("Input rect (NSScreen): \(rect)")
        ssLog("Converted rect (CG): \(cgRect)")

        // Exclude our own app from capture
        let excludedApps = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        let config = makeConfig(rect: cgRect, fps: fps, audio: audio)

        let frameHandler = onFrameReceived
        let output = StreamOutput { surface in
            frameHandler?(surface)
        }
        self.streamOutput = output

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: videoQueue)
        if audio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)
        }

        try await stream.startCapture()
        self.stream = stream
        isCapturing = true
    }

    /// Stops the capture stream.
    func stopCapture() async throws {
        guard isCapturing, let stream = stream else { return }
        try await stream.stopCapture()
        self.stream = nil
        self.streamOutput = nil
        isCapturing = false
    }

    /// Updates the capture region without restarting.
    /// Input rect is in NSScreen coordinates (bottom-left origin).
    func updateCaptureRect(_ newRect: CGRect) async throws {
        guard isCapturing, let stream = stream, let display = currentDisplay else { return }
        let displayFrame = display.frame
        let relativeX = newRect.origin.x - displayFrame.origin.x
        let relativeY = displayFrame.height - (newRect.origin.y - displayFrame.origin.y) - newRect.height
        let cgRect = CGRect(x: relativeX, y: relativeY, width: newRect.width, height: newRect.height)
        captureRect = cgRect
        let config = makeConfig(rect: cgRect, fps: currentFPS, audio: isAudioEnabled)
        try await stream.updateConfiguration(config)
    }

    /// Toggles audio capture.
    func setAudio(_ enabled: Bool) async throws {
        guard isCapturing, let stream = stream else { return }
        isAudioEnabled = enabled
        let config = makeConfig(rect: captureRect, fps: currentFPS, audio: enabled)
        try await stream.updateConfiguration(config)
    }

    // MARK: - Private

    private func makeConfig(rect: CGRect, fps: Int, audio: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int(rect.width)
        config.height = Int(rect.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 4
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = true
        config.capturesAudio = audio
        if audio {
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
        }
        config.backgroundColor = .black
        return config
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            isCapturing = false
            print("ScreenSlice: Stream stopped with error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Stream Output

private final class StreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let onSurface: @Sendable (IOSurface) -> Void

    init(onSurface: @escaping @Sendable (IOSurface) -> Void) {
        self.onSurface = onSurface
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid else { return }

        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachment = attachments.first,
              let statusRaw = attachment[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else {
            return
        }

        guard let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
            return
        }

        let ioSurface = unsafeBitCast(surface, to: IOSurface.self)
        onSurface(ioSurface)
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noDisplayFound

    var errorDescription: String? {
        switch self {
        case .noDisplayFound: return "No display found."
        }
    }
}
