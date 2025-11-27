//
//  PacketSample.swift
//  BitrateReader
//
//  Created by skeeet on 11/27/25.
//

import Foundation
import CoreMedia

/// Represents a single compressed video packet with its timestamp and size
struct PacketSample: Identifiable, Sendable {
    let id = UUID()
    let index: Int
    let presentationTime: CMTime  // Rational time (num/denom with timebase)
    let sizeBytes: Int64          // Packet size in bytes
    let isKeyframe: Bool          // True if this is a sync/keyframe (I-frame)
    let timeInSeconds: Double?    // Pre-computed time in seconds (nil if invalid)

    /// Create a packet sample with pre-computed time conversion
    nonisolated init(index: Int, presentationTime: CMTime, sizeBytes: Int64, isKeyframe: Bool) {
        self.index = index
        self.presentationTime = presentationTime
        self.sizeBytes = sizeBytes
        self.isKeyframe = isKeyframe

        // Pre-compute time conversion once during initialization
        if CMTIME_IS_VALID(presentationTime) && CMTIME_IS_NUMERIC(presentationTime) {
            let seconds = CMTimeGetSeconds(presentationTime)
            self.timeInSeconds = seconds.isFinite ? seconds : nil
        } else {
            self.timeInSeconds = nil
        }
    }
}
