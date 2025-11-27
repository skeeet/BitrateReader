//
//  VideoPacketAnalyzer.swift
//  BitrateReader
//
//  Created by skeeet on 11/27/25.
//

import Foundation
import AVFoundation

/// Service for analyzing compressed video packets using AVFoundation
actor VideoPacketAnalyzer {

    /// Progress callback closure
    typealias ProgressCallback = (Double) -> Void

    /// Result of video analysis
    struct AnalysisResult {
        let packets: [PacketSample]
        let metadata: VideoMetadata
    }

    // MARK: - Public API

    /// Analyzes a video file and extracts packet information
    /// - Parameters:
    ///   - url: URL to the video file
    ///   - progressCallback: Optional callback for progress updates (0.0 to 1.0)
    /// - Returns: Analysis result containing packets and metadata
    /// - Throws: AnalysisError if analysis fails
    func analyze(url: URL, progressCallback: ProgressCallback? = nil) async throws -> AnalysisResult {
        // Create asset
        let asset = AVURLAsset(url: url)

        // Load metadata
        let metadata = try await loadMetadata(from: asset, url: url)

        // Find video track
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AnalysisError.noVideoTrack
        }

        // Extract packets
        let packets = try await extractPackets(
            from: asset,
            videoTrack: videoTrack,
            duration: metadata.durationSeconds,
            progressCallback: progressCallback
        )

        return AnalysisResult(packets: packets, metadata: metadata)
    }

    // MARK: - Private Methods

    /// Loads video metadata from the asset
    private func loadMetadata(from asset: AVURLAsset, url: URL) async throws -> VideoMetadata {
        do {
            // Load duration
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)

            guard durationSeconds.isFinite && durationSeconds > 0 else {
                throw AnalysisError.metadataLoadFailed
            }

            // Load tracks to check if readable
            let tracks = try await asset.load(.tracks)
            guard !tracks.isEmpty else {
                throw AnalysisError.noVideoTrack
            }

            // Get file size
            var fileSizeBytes: Int64?
            if url.isFileURL {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fileSize = attributes[.size] as? Int64 {
                    fileSizeBytes = fileSize
                }
            }

            // Estimate frame count (will be refined during analysis)
            let videoTrack = try await asset.loadTracks(withMediaType: .video).first
            var frameCountEstimate: Int?
            if let track = videoTrack {
                let nominalFrameRate = try await track.load(.nominalFrameRate)
                if nominalFrameRate > 0 {
                    let estimatedFrames = durationSeconds * Double(nominalFrameRate)
                    // Safely convert to Int, checking for overflow
                    if estimatedFrames.isFinite && estimatedFrames >= 0 && estimatedFrames <= Double(Int.max) {
                        frameCountEstimate = Int(estimatedFrames)
                    }
                }
            }

            // Get codec description
            var codecDescription: String?
            if let track = videoTrack {
                let formatDescriptions = try await track.load(.formatDescriptions)
                if let formatDescription = formatDescriptions.first {
                    let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
                    codecDescription = fourCharCodeToString(mediaSubType)
                }
            }

            return VideoMetadata(
                durationSeconds: durationSeconds,
                frameCountEstimate: frameCountEstimate,
                codecDescription: codecDescription,
                fileName: url.lastPathComponent,
                filePath: url.path,
                fileSizeBytes: fileSizeBytes
            )

        } catch let error as AnalysisError {
            throw error
        } catch {
            throw AnalysisError.metadataLoadFailed
        }
    }

    /// Extracts packet samples from the video track
    private func extractPackets(
        from asset: AVAsset,
        videoTrack: AVAssetTrack,
        duration: Double,
        progressCallback: ProgressCallback?
    ) async throws -> [PacketSample] {

        // Create reader
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AnalysisError.readerSetupFailed
        }

        // outputSettings = nil is critical: gives us compressed packets without decoding
        // This allows reading the actual encoded packet sizes rather than decoded frame sizes
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: nil
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw AnalysisError.readerSetupFailed
        }

        reader.add(output)

        guard reader.startReading() else {
            if let error = reader.error {
                throw AnalysisError.readerFailed(error.localizedDescription)
            }
            throw AnalysisError.readerStartFailed
        }

        // Ensure reader cleanup on all exit paths (normal, error, cancellation)
        defer {
            if reader.status == .reading {
                reader.cancelReading()
            }
        }

        var packets: [PacketSample] = []
        var index = 0

        while reader.status == .reading {
            // Check cancellation early to avoid processing thousands of packets unnecessarily
            if Task.isCancelled {
                reader.cancelReading()
                throw AnalysisError.cancelled
            }

            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                break
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            guard CMTIME_IS_VALID(presentationTime) && CMTIME_IS_NUMERIC(presentationTime) else {
                continue
            }

            let sizeBytes = Int64(CMSampleBufferGetTotalSampleSize(sampleBuffer))

            guard sizeBytes > 0 else {
                continue
            }

            let isKeyframe = isKeyframeSample(sampleBuffer)

            let packet = PacketSample(
                index: index,
                presentationTime: presentationTime,
                sizeBytes: sizeBytes,
                isKeyframe: isKeyframe
            )
            packets.append(packet)

            if let callback = progressCallback, duration > 0 {
                let timeSeconds = CMTimeGetSeconds(presentationTime)
                if timeSeconds.isFinite {
                    let progress = min(timeSeconds / duration, 1.0)
                    callback(progress)
                }
            }

            index += 1
        }

        if reader.status == .failed {
            if let error = reader.error {
                throw AnalysisError.readerFailed(error.localizedDescription)
            }
            throw AnalysisError.readerFailed("Unknown error")
        } else if reader.status == .cancelled {
            throw AnalysisError.cancelled
        }

        // Files may store packets in decode order (DTS), but we need presentation order (PTS)
        // This is critical for B-frame codecs where decode order != display order
        let sortedPackets = packets.sorted { packet1, packet2 in
            CMTimeCompare(packet1.presentationTime, packet2.presentationTime) < 0
        }

        // Re-index to match presentation order for UI display
        let reindexedPackets = sortedPackets.enumerated().map { (newIndex, packet) in
            PacketSample(
                index: newIndex,
                presentationTime: packet.presentationTime,
                sizeBytes: packet.sizeBytes,
                isKeyframe: packet.isKeyframe
            )
        }

        return reindexedPackets
    }

    // MARK: - Helper Methods

    private func isKeyframeSample(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
              let attachments = attachmentsArray.first else {
            // No attachments = keyframe (common for first frame or all-intra codecs)
            return true
        }

        if let notSync = attachments[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync  // Key present: notSync=false means IS a keyframe
        }

        // Key missing = sync sample by convention
        return true
    }

    private func fourCharCodeToString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "unknown"
    }
}
