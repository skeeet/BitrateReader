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

    // Track security-scoped resource access for sandboxed file operations
    private var isAccessingSecurityScopedResource = false

    // Throttle progress updates to avoid creating thousands of short-lived Tasks
    private var lastProgressUpdate: Date = .distantPast

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

    // Required for drag-and-drop files in sandboxed apps
    // Must be balanced with stopAccessingResource to avoid resource leaks
    func startAccessingResource() {
        guard let url = selectedFileURL else { return }
        if url.startAccessingSecurityScopedResource() {
            isAccessingSecurityScopedResource = true
        }
    }

    private func stopAccessingResource() {
        guard isAccessingSecurityScopedResource, let url = selectedFileURL else { return }
        url.stopAccessingSecurityScopedResource()
        isAccessingSecurityScopedResource = false
    }

    func analyzeFile(at url: URL) {
        guard canSelectFile else { return }

        stopAccessingResource()

        selectedFileURL = url
        state = .loadingMetadata

        analysisTask?.cancel()
        lastProgressUpdate = .distantPast

        analysisTask = Task {
            do {
                await MainActor.run {
                    self.state = .analyzing(progress: 0.0)
                }

                let result = try await analyzer.analyze(url: url) { progress in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }

                        // Throttle to 10 updates/sec - video files can have 60,000+ packets
                        // Without throttling, we'd create a Task for every packet (huge overhead)
                        let now = Date()
                        let timeSinceLastUpdate = now.timeIntervalSince(self.lastProgressUpdate)

                        if timeSinceLastUpdate >= 0.1 || progress >= 1.0 {
                            if case .analyzing = self.state {
                                self.state = .analyzing(progress: progress)
                                self.lastProgressUpdate = now
                            }
                        }
                    }
                }

                if Task.isCancelled {
                    await MainActor.run {
                        self.state = .failed(message: "Analysis was cancelled")
                    }
                    return
                }

                await MainActor.run {
                    self.state = .finished(
                        packets: result.packets,
                        metadata: result.metadata
                    )
                }

            } catch let error as AnalysisError {
                await MainActor.run {
                    self.state = .failed(message: error.localizedDescription)
                    self.stopAccessingResource()
                }
            } catch {
                await MainActor.run {
                    self.state = .failed(message: "An unexpected error occurred: \(error.localizedDescription)")
                    self.stopAccessingResource()
                }
            }
        }
    }

    func reset() {
        analysisTask?.cancel()
        analysisTask = nil
        stopAccessingResource()
        state = .idle
        selectedFileURL = nil
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        stopAccessingResource()
        state = .idle
    }
}
