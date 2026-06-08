import AVFoundation
import Darwin
import Foundation

private let sckWebcamStatusOK: Int32 = 0
private let sckWebcamStatusInvalidArgument: Int32 = -1
private let sckWebcamStatusNoDevice: Int32 = -2
private let sckWebcamStatusInputUnavailable: Int32 = -3
private let sckWebcamStatusOutputUnavailable: Int32 = -4
private let sckWebcamStatusStartFailed: Int32 = -5
private let sckWebcamStatusStopFailed: Int32 = -6
private let sckWebcamStatusOutputFileUnavailable: Int32 = -7
private let sckWebcamStatusCancelled: Int32 = -8

public struct SCKWebcamDevice {
    public var stableID: UnsafeMutablePointer<CChar>?
    public var displayName: UnsafeMutablePointer<CChar>?
}

private final class WebcamRecorderBridge: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let outputURL: URL
    private let preferredDeviceID: String
    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "com.vivyshot.rust.webcam-recorder", qos: .userInitiated)

    private var startSemaphore: DispatchSemaphore?
    private var stopSemaphore: DispatchSemaphore?
    private var lastStatus = sckWebcamStatusOK
    private(set) var recordingStartUptimeSeconds: Double = 0

    init(outputPath: String, preferredDeviceID: String) {
        outputURL = URL(fileURLWithPath: outputPath)
        self.preferredDeviceID = preferredDeviceID
        super.init()
    }

    var previewSessionPointer: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(session).toOpaque()
    }

    func prepare() -> Int32 {
        queue.sync {
            configureSession()
        }
    }

    func start() -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        startSemaphore = semaphore
        lastStatus = sckWebcamStatusStartFailed
        recordingStartUptimeSeconds = 0

        queue.async {
            do {
                if FileManager.default.fileExists(atPath: self.outputURL.path) {
                    try FileManager.default.removeItem(at: self.outputURL)
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                if !self.movieOutput.isRecording {
                    self.movieOutput.startRecording(to: self.outputURL, recordingDelegate: self)
                }
            } catch {
                self.lastStatus = sckWebcamStatusStartFailed
                semaphore.signal()
            }
        }

        if semaphore.wait(timeout: .now() + 5.0) == .timedOut {
            queue.async {
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                }
                if self.session.isRunning {
                    self.session.stopRunning()
                }
            }
            return sckWebcamStatusStartFailed
        }
        return lastStatus
    }

    func stop() -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        stopSemaphore = semaphore
        lastStatus = sckWebcamStatusStopFailed

        queue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            } else {
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                self.lastStatus = self.validateOutputFile()
                semaphore.signal()
            }
        }

        if semaphore.wait(timeout: .now() + 4.0) == .timedOut {
            cancel()
            return sckWebcamStatusStopFailed
        }
        return lastStatus
    }

    func cancel() {
        queue.async {
            self.lastStatus = sckWebcamStatusCancelled
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.startSemaphore?.signal()
            self.stopSemaphore?.signal()
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        queue.async {
            self.recordingStartUptimeSeconds = ProcessInfo.processInfo.systemUptime
            self.lastStatus = sckWebcamStatusOK
            self.startSemaphore?.signal()
            self.startSemaphore = nil
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }

            if let error, !Self.isSuccessfullyFinishedRecordingError(error) {
                self.lastStatus = sckWebcamStatusStopFailed
            } else {
                self.lastStatus = self.validateOutputFile()
            }
            self.startSemaphore?.signal()
            self.startSemaphore = nil
            self.stopSemaphore?.signal()
            self.stopSemaphore = nil
        }
    }

    private func configureSession() -> Int32 {
        session.beginConfiguration()
        session.sessionPreset = .high
        defer {
            session.commitConfiguration()
        }

        guard let device = Self.selectedDevice(preferredDeviceID: preferredDeviceID) else {
            return sckWebcamStatusNoDevice
        }

        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            return sckWebcamStatusInputUnavailable
        }
        session.addInput(input)

        guard session.canAddOutput(movieOutput) else {
            return sckWebcamStatusOutputUnavailable
        }
        session.addOutput(movieOutput)
        movieOutput.movieFragmentInterval = .invalid
        return sckWebcamStatusOK
    }

    private func validateOutputFile() -> Int32 {
        guard FileManager.default.fileExists(atPath: outputURL.path),
              let values = try? outputURL.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) > 0
        else {
            return sckWebcamStatusOutputFileUnavailable
        }
        return sckWebcamStatusOK
    }

    private static func isSuccessfullyFinishedRecordingError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
    }

    private static func selectedDevice(preferredDeviceID: String) -> AVCaptureDevice? {
        let devices = discoverDevices()
        return devices.first(where: { $0.uniqueID == preferredDeviceID })
            ?? AVCaptureDevice.default(for: .video)
            ?? devices.first
    }

    static func discoverDevices() -> [AVCaptureDevice] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.external)
        } else {
            deviceTypes.append(.externalUnknown)
        }
        if #available(macOS 15.0, *) {
            deviceTypes.append(.continuityCamera)
        }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices
    }
}

@_cdecl("sck_webcam_recorder_create")
public func sck_webcam_recorder_create(
    _ outputPathUTF8: UnsafePointer<UInt8>?,
    _ outputPathLen: UInt32,
    _ deviceIDUTF8: UnsafePointer<UInt8>?,
    _ deviceIDLen: UInt32
) -> UnsafeMutableRawPointer? {
    guard let outputPathUTF8, outputPathLen > 0 else {
        return nil
    }
    let outputPath = String(
        decoding: UnsafeBufferPointer(start: outputPathUTF8, count: Int(outputPathLen)),
        as: UTF8.self
    )
    let deviceID = deviceIDUTF8.map {
        String(decoding: UnsafeBufferPointer(start: $0, count: Int(deviceIDLen)), as: UTF8.self)
    } ?? ""
    let recorder = WebcamRecorderBridge(outputPath: outputPath, preferredDeviceID: deviceID)
    guard recorder.prepare() == sckWebcamStatusOK else {
        return nil
    }
    return Unmanaged.passRetained(recorder).toOpaque()
}

@_cdecl("sck_webcam_recorder_preview_session")
public func sck_webcam_recorder_preview_session(_ recorderPtr: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let recorderPtr else {
        return nil
    }
    let recorder = Unmanaged<WebcamRecorderBridge>.fromOpaque(recorderPtr).takeUnretainedValue()
    return recorder.previewSessionPointer
}

@_cdecl("sck_webcam_recorder_start")
public func sck_webcam_recorder_start(_ recorderPtr: UnsafeMutableRawPointer?) -> Int32 {
    guard let recorderPtr else {
        return sckWebcamStatusInvalidArgument
    }
    let recorder = Unmanaged<WebcamRecorderBridge>.fromOpaque(recorderPtr).takeUnretainedValue()
    return recorder.start()
}

@_cdecl("sck_webcam_recorder_stop")
public func sck_webcam_recorder_stop(_ recorderPtr: UnsafeMutableRawPointer?) -> Int32 {
    guard let recorderPtr else {
        return sckWebcamStatusInvalidArgument
    }
    let recorder = Unmanaged<WebcamRecorderBridge>.fromOpaque(recorderPtr).takeUnretainedValue()
    return recorder.stop()
}

@_cdecl("sck_webcam_recorder_cancel")
public func sck_webcam_recorder_cancel(_ recorderPtr: UnsafeMutableRawPointer?) {
    guard let recorderPtr else {
        return
    }
    let recorder = Unmanaged<WebcamRecorderBridge>.fromOpaque(recorderPtr).takeUnretainedValue()
    recorder.cancel()
}

@_cdecl("sck_webcam_recorder_start_uptime_seconds")
public func sck_webcam_recorder_start_uptime_seconds(_ recorderPtr: UnsafeMutableRawPointer?) -> Double {
    guard let recorderPtr else {
        return 0
    }
    let recorder = Unmanaged<WebcamRecorderBridge>.fromOpaque(recorderPtr).takeUnretainedValue()
    return recorder.recordingStartUptimeSeconds
}

@_cdecl("sck_webcam_recorder_destroy")
public func sck_webcam_recorder_destroy(_ recorderPtr: UnsafeMutableRawPointer?) {
    guard let recorderPtr else {
        return
    }
    Unmanaged<WebcamRecorderBridge>.fromOpaque(recorderPtr).release()
}

@_cdecl("sck_webcam_copy_devices")
public func sck_webcam_copy_devices(
    _ outDevices: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    _ outCount: UnsafeMutablePointer<UInt32>?
) -> Int32 {
    guard let outDevices, let outCount else {
        return sckWebcamStatusInvalidArgument
    }
    let devices = WebcamRecorderBridge.discoverDevices()
        .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    guard !devices.isEmpty else {
        outDevices.pointee = nil
        outCount.pointee = 0
        return sckWebcamStatusOK
    }

    let buffer = UnsafeMutablePointer<SCKWebcamDevice>.allocate(capacity: devices.count)
    for (index, device) in devices.enumerated() {
        buffer.advanced(by: index).initialize(to: SCKWebcamDevice(
            stableID: strdup(device.uniqueID),
            displayName: strdup(device.localizedName)
        ))
    }
    outDevices.pointee = UnsafeMutableRawPointer(buffer)
    outCount.pointee = UInt32(devices.count)
    return sckWebcamStatusOK
}

@_cdecl("sck_webcam_devices_free")
public func sck_webcam_devices_free(_ devicesPtr: UnsafeMutableRawPointer?, _ count: UInt32) {
    guard let devicesPtr, count > 0 else {
        return
    }
    let devices = devicesPtr.assumingMemoryBound(to: SCKWebcamDevice.self)
    for index in 0..<Int(count) {
        let device = devices.advanced(by: index).pointee
        free(device.stableID)
        free(device.displayName)
        devices.advanced(by: index).deinitialize(count: 1)
    }
    devices.deallocate()
}
