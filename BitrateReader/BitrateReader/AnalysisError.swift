//
//  AnalysisError.swift
//  BitrateReader
//
//  Created by skeeet on 11/27/25.
//

import Foundation

/// Errors that can occur during video packet analysis
enum AnalysisError: LocalizedError {
    case fileNotAccessible
    case metadataLoadFailed
    case noVideoTrack
    case readerSetupFailed
    case readerStartFailed
    case readerFailed(String)
    case protectedContent
    case unsupportedFormat
    case cancelled

    var errorDescription: String? {
        switch self {
        case .fileNotAccessible:
            return "Unable to access the video file."
        case .metadataLoadFailed:
            return "Failed to load video metadata."
        case .noVideoTrack:
            return "No video track found in the file."
        case .readerSetupFailed:
            return "Failed to set up video reader."
        case .readerStartFailed:
            return "Failed to start reading video samples."
        case .readerFailed(let details):
            return "Reader failed: \(details)"
        case .protectedContent:
            return "This file contains protected content and cannot be analyzed."
        case .unsupportedFormat:
            return "This video format is not supported."
        case .cancelled:
            return "Analysis was cancelled."
        }
    }
}
