//
//  PacketAnalysisViewModel.swift
//  BitrateReader
//
//  Created by skeeet on 11/27/25.
//

import Foundation
import SwiftUI
import Combine

/// View model managing video packet analysis state and operations
@MainActor
class PacketAnalysisViewModel: ObservableObject {

    // MARK: - State

    enum AnalysisState {
        case idle
        case loadingMetadata
        case analyzing(progress: Double)
        case finished(packets: [PacketSample], metadata: VideoMetadata)
        case failed(message: String)
    }

    // MARK: - Published Properties

    @Published private(set) var state: AnalysisState = .idle
    @Published private(set) var selectedFileURL: URL?

    // MARK: - Private Properties

    private let analyzer = VideoPacketAnalyzer()
    private var analysisTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var isAnalyzing: Bool {
        if case .analyzing = state {
            return true
        }
        if case .loadingMetadata = state {
            return true
        }
        return false
    }

    var canSelectFile: Bool {
        !isAnalyzing
    }

    // MARK: - Public Methods

    /// Starts analysis of a video file
    func analyzeFile(at url: URL) {
        guard canSelectFile else { return }

        selectedFileURL = url
        state = .loadingMetadata

        // Cancel any existing analysis
        analysisTask?.cancel()

        // Start new analysis task
        analysisTask = Task {
            do {
                // Update to analyzing state
                await MainActor.run {
                    self.state = .analyzing(progress: 0.0)
                }

                // Perform analysis with progress updates
                let result = try await analyzer.analyze(url: url) { progress in
                    Task { @MainActor in
                        if case .analyzing = self.state {
                            self.state = .analyzing(progress: progress)
                        }
                    }
                }

                // Check if task was cancelled
                if Task.isCancelled {
                    await MainActor.run {
                        self.state = .failed(message: "Analysis was cancelled")
                    }
                    return
                }

                // Update to finished state
                await MainActor.run {
                    self.state = .finished(
                        packets: result.packets,
                        metadata: result.metadata
                    )
                }

            } catch let error as AnalysisError {
                await MainActor.run {
                    self.state = .failed(message: error.localizedDescription)
                }
            } catch {
                await MainActor.run {
                    self.state = .failed(message: "An unexpected error occurred: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Resets the analysis state to idle
    func reset() {
        analysisTask?.cancel()
        analysisTask = nil
        state = .idle
        selectedFileURL = nil
    }

    /// Cancels the current analysis
    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        state = .idle
    }
}
