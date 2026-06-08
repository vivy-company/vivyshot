import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import VideoToolbox

private let sckSoftwareWriterStatusOK: Int32 = 0
private let sckSoftwareWriterStatusInvalidArgument: Int32 = -1
private let sckSoftwareWriterStatusWriterSetupFailed: Int32 = -2
private let sckSoftwareWriterStatusVideoInputUnavailable: Int32 = -3
private let sckSoftwareWriterStatusSystemAudioInputUnavailable: Int32 = -4
private let sckSoftwareWriterStatusMicrophoneInputUnavailable: Int32 = -5
private let sckSoftwareWriterStatusStartFailed: Int32 = -6
private let sckSoftwareWriterStatusNoFrames: Int32 = -7
private let sckSoftwareWriterStatusFinishFailed: Int32 = -8
private let sckSoftwareWriterStatusCancelled: Int32 = -9
private let sckSoftwareWriterStatusIncomplete: Int32 = -10

private final class SoftwareH264Writer {
    private let queue = DispatchQueue(label: "com.vivyshot.rust.software-h264-writer", qos: .userInitiated)
    private let outputURL: URL
    private let frameRate: Int
    private let includeSystemAudio: Bool
    private let includeMicrophoneAudio: Bool

    private var configuredVideoSize: CGSize?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneAudioInput: AVAssetWriterInput?
    private var sessionStartTime: CMTime?
    private var didFinish = false

    init(outputPath: String, frameRate: Int, includeSystemAudio: Bool, includeMicrophoneAudio: Bool) {
        self.outputURL = URL(fileURLWithPath: outputPath)
        self.frameRate = max(1, frameRate)
        self.includeSystemAudio = includeSystemAudio
        self.includeMicrophoneAudio = includeMicrophoneAudio
    }

    func configureVideoSize(width: Int, height: Int) {
        queue.sync {
            configuredVideoSize = CGSize(width: max(2, width), height: max(2, height))
        }
    }

    func prepare() -> Int32 {
        queue.sync {
            guard let videoSize = configuredVideoSize else {
                return sckSoftwareWriterStatusInvalidArgument
            }

            do {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }

                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
                writer.shouldOptimizeForNetworkUse = true

                let bitrate = max(6_000_000, Int(videoSize.width * videoSize.height * CGFloat(frameRate) * 0.12))
                let videoInput = AVAssetWriterInput(
                    mediaType: .video,
                    outputSettings: [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoWidthKey: Int(videoSize.width),
                        AVVideoHeightKey: Int(videoSize.height),
                        AVVideoEncoderSpecificationKey: [
                            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false
                        ],
                        AVVideoCompressionPropertiesKey: [
                            AVVideoAverageBitRateKey: bitrate,
                            AVVideoExpectedSourceFrameRateKey: frameRate,
                            AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
                            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                        ]
                    ]
                )
                videoInput.expectsMediaDataInRealTime = true
                guard writer.canAdd(videoInput) else {
                    return sckSoftwareWriterStatusVideoInputUnavailable
                }
                writer.add(videoInput)

                if includeSystemAudio {
                    let input = makeAudioInput()
                    guard writer.canAdd(input) else {
                        return sckSoftwareWriterStatusSystemAudioInputUnavailable
                    }
                    writer.add(input)
                    systemAudioInput = input
                }

                if includeMicrophoneAudio {
                    let input = makeAudioInput()
                    guard writer.canAdd(input) else {
                        return sckSoftwareWriterStatusMicrophoneInputUnavailable
                    }
                    writer.add(input)
                    microphoneAudioInput = input
                }

                guard writer.startWriting() else {
                    return sckSoftwareWriterStatusStartFailed
                }

                self.writer = writer
                self.videoInput = videoInput
                return sckSoftwareWriterStatusOK
            } catch {
                return sckSoftwareWriterStatusWriterSetupFailed
            }
        }
    }

    func append(sampleBuffer: CMSampleBuffer, outputType: Int32) {
        queue.sync {
            guard CMSampleBufferDataIsReady(sampleBuffer), !didFinish else {
                return
            }

            switch outputType {
            case 0:
                appendVideo(sampleBuffer)
            case 1:
                appendAudio(sampleBuffer, input: systemAudioInput)
            case 2:
                appendAudio(sampleBuffer, input: microphoneAudioInput)
            default:
                return
            }
        }
    }

    func finish() -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var status = sckSoftwareWriterStatusOK

        queue.async {
            self.didFinish = true

            guard let writer = self.writer else {
                semaphore.signal()
                return
            }

            guard self.sessionStartTime != nil else {
                writer.cancelWriting()
                status = sckSoftwareWriterStatusNoFrames
                semaphore.signal()
                return
            }

            self.videoInput?.markAsFinished()
            self.systemAudioInput?.markAsFinished()
            self.microphoneAudioInput?.markAsFinished()

            writer.finishWriting {
                switch writer.status {
                case .completed:
                    status = sckSoftwareWriterStatusOK
                case .failed:
                    status = sckSoftwareWriterStatusFinishFailed
                case .cancelled:
                    status = sckSoftwareWriterStatusCancelled
                default:
                    status = sckSoftwareWriterStatusIncomplete
                }
                semaphore.signal()
            }
        }

        semaphore.wait()
        return status
    }

    func cancel() {
        queue.async {
            self.didFinish = true
            self.writer?.cancelWriting()
        }
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let writer, writer.status == .writing, let videoInput else {
            return
        }
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
            return
        }
        guard isCompleteScreenFrame(sampleBuffer) else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid else {
            return
        }

        if sessionStartTime == nil {
            sessionStartTime = presentationTime
            writer.startSession(atSourceTime: presentationTime)
        }

        guard videoInput.isReadyForMoreMediaData else {
            return
        }
        _ = videoInput.append(sampleBuffer)
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, input: AVAssetWriterInput?) {
        guard let input, input.isReadyForMoreMediaData, sessionStartTime != nil else {
            return
        }
        _ = input.append(sampleBuffer)
    }

    private func makeAudioInput() -> AVAssetWriterInput {
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
        )
        input.expectsMediaDataInRealTime = true
        return input
    }

    private func isCompleteScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let statusValue = attachments.first?[SCStreamFrameInfo.status] as? Int,
            let status = SCFrameStatus(rawValue: statusValue)
        else {
            return true
        }
        return status == .complete || status == .started
    }
}

@_cdecl("sck_software_h264_writer_create")
public func sck_software_h264_writer_create(
    _ pathUTF8: UnsafePointer<UInt8>?,
    _ pathLen: UInt32,
    _ frameRate: UInt32,
    _ includeSystemAudio: Bool,
    _ includeMicrophoneAudio: Bool
) -> UnsafeMutableRawPointer? {
    guard let pathUTF8, pathLen > 0 else {
        return nil
    }

    let path = String(decoding: UnsafeBufferPointer(start: pathUTF8, count: Int(pathLen)), as: UTF8.self)
    guard !path.isEmpty else {
        return nil
    }

    let writer = SoftwareH264Writer(
        outputPath: path,
        frameRate: Int(frameRate),
        includeSystemAudio: includeSystemAudio,
        includeMicrophoneAudio: includeMicrophoneAudio
    )
    return Unmanaged.passRetained(writer).toOpaque()
}

@_cdecl("sck_software_h264_writer_configure_video_size")
public func sck_software_h264_writer_configure_video_size(
    _ writerPtr: UnsafeMutableRawPointer?,
    _ width: UInt32,
    _ height: UInt32
) -> Int32 {
    guard let writerPtr, width > 0, height > 0 else {
        return sckSoftwareWriterStatusInvalidArgument
    }
    let writer = Unmanaged<SoftwareH264Writer>.fromOpaque(writerPtr).takeUnretainedValue()
    writer.configureVideoSize(width: Int(width), height: Int(height))
    return sckSoftwareWriterStatusOK
}

@_cdecl("sck_software_h264_writer_prepare")
public func sck_software_h264_writer_prepare(_ writerPtr: UnsafeMutableRawPointer?) -> Int32 {
    guard let writerPtr else {
        return sckSoftwareWriterStatusInvalidArgument
    }
    let writer = Unmanaged<SoftwareH264Writer>.fromOpaque(writerPtr).takeUnretainedValue()
    return writer.prepare()
}

@_cdecl("sck_software_h264_writer_append")
public func sck_software_h264_writer_append(
    _ writerPtr: UnsafeMutableRawPointer?,
    _ sampleBufferPtr: UnsafeMutableRawPointer?,
    _ outputType: Int32
) {
    guard let writerPtr, let sampleBufferPtr else {
        return
    }
    let writer = Unmanaged<SoftwareH264Writer>.fromOpaque(writerPtr).takeUnretainedValue()
    let sampleBuffer = Unmanaged<CMSampleBuffer>.fromOpaque(sampleBufferPtr).takeUnretainedValue()
    writer.append(sampleBuffer: sampleBuffer, outputType: outputType)
}

@_cdecl("sck_software_h264_writer_finish")
public func sck_software_h264_writer_finish(_ writerPtr: UnsafeMutableRawPointer?) -> Int32 {
    guard let writerPtr else {
        return sckSoftwareWriterStatusInvalidArgument
    }
    let writer = Unmanaged<SoftwareH264Writer>.fromOpaque(writerPtr).takeUnretainedValue()
    return writer.finish()
}

@_cdecl("sck_software_h264_writer_cancel")
public func sck_software_h264_writer_cancel(_ writerPtr: UnsafeMutableRawPointer?) {
    guard let writerPtr else {
        return
    }
    let writer = Unmanaged<SoftwareH264Writer>.fromOpaque(writerPtr).takeUnretainedValue()
    writer.cancel()
}

@_cdecl("sck_software_h264_writer_destroy")
public func sck_software_h264_writer_destroy(_ writerPtr: UnsafeMutableRawPointer?) {
    guard let writerPtr else {
        return
    }
    Unmanaged<SoftwareH264Writer>.fromOpaque(writerPtr).release()
}
