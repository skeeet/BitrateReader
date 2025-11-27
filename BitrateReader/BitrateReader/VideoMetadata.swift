//
//  VideoMetadata.swift
//  BitrateReader
//
//  Created by skeeet on 11/27/25.
//

import Foundation

/// Metadata about the analyzed video file
struct VideoMetadata: Sendable {
    let durationSeconds: Double
    let frameCountEstimate: Int?
    let codecDescription: String?
    let fileName: String?
    let filePath: String?
    let fileSizeBytes: Int64?
}
