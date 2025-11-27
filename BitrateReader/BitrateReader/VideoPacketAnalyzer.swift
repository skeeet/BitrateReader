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

        // Configure output for compressed samples (outputSettings = nil)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: nil
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw AnalysisError.readerSetupFailed
        }

        reader.add(output)

        // Start reading
        guard reader.startReading() else {
            if let error = reader.error {
                throw AnalysisError.readerFailed(error.localizedDescription)
            }
            throw AnalysisError.readerStartFailed
        }

        // Extract all packets
        var packets: [PacketSample] = []
        var index = 0

        // Read samples in a loop (this is already async-friendly)
        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                break
            }

            // Extract timestamp (keep as CMTime - rational time)
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            // Skip invalid timestamps
            guard CMTIME_IS_VALID(presentationTime) && CMTIME_IS_NUMERIC(presentationTime) else {
                continue
            }

            // Extract size (use Int64 for packet size)
            let sizeBytes = Int64(CMSampleBufferGetTotalSampleSize(sampleBuffer))

            // Skip zero-byte packets (shouldn't exist for valid video frames)
            guard sizeBytes > 0 else {
                continue
            }

            // Detect if this is a keyframe (sync sample)
            let isKeyframe = isKeyframeSample(sampleBuffer)

            // Create packet sample
            let packet = PacketSample(
                index: index,
                presentationTime: presentationTime,
                sizeBytes: sizeBytes,
                isKeyframe: isKeyframe
            )
            packets.append(packet)

            // Report progress (only convert to seconds for progress reporting)
            if let callback = progressCallback, duration > 0 {
                let timeSeconds = CMTimeGetSeconds(presentationTime)
                if timeSeconds.isFinite {
                    let progress = min(timeSeconds / duration, 1.0)
                    callback(progress)
                }
            }

            index += 1
        }

        // Check final status
        if reader.status == .failed {
            if let error = reader.error {
                throw AnalysisError.readerFailed(error.localizedDescription)
            }
            throw AnalysisError.readerFailed("Unknown error")
        } else if reader.status == .cancelled {
            throw AnalysisError.cancelled
        }

        // Sort packets by presentation time (PTS) to ensure correct order
        // Files may store packets in decode order, but we display in presentation order
        let sortedPackets = packets.sorted { packet1, packet2 in
            CMTimeCompare(packet1.presentationTime, packet2.presentationTime) < 0
        }

        // Re-index packets based on presentation order
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

    /// Checks if a sample buffer represents a keyframe (sync sample)
    /// - Parameter sampleBuffer: The sample buffer to check
    /// - Returns: True if this is a keyframe/I-frame, false otherwise
    private func isKeyframeSample(_ sampleBuffer: CMSampleBuffer) -> Bool {
        // Get the sample attachments array
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
              let attachments = attachmentsArray.first else {
            // If no attachments, assume it's a keyframe (safe default for first frame)
            return true
        }

        // Check for kCMSampleAttachmentKey_NotSync
        // If this key is missing or false, the sample is a sync/keyframe
        if let notSync = attachments[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync  // If notSync is false, it IS a keyframe
        }

        // If the key is missing, it's a sync sample (keyframe)
        return true
    }

    /// Converts a FourCharCode to a readable string
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
