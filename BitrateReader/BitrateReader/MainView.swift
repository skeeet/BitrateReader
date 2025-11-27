//
//  MainView.swift
//  BitrateReader
//
//  Created by skeeet on 11/27/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Main view for the video packet analyzer application
struct MainView: View {

    @StateObject private var viewModel = PacketAnalysisViewModel()

    private var navigationTitleText: String {
        switch viewModel.state {
        case .finished(_, let metadata):
            return metadata.fileName ?? "Video Packet Analyzer"
        default:
            if let url = viewModel.selectedFileURL {
                return url.lastPathComponent
            }
            return "Video Packet Analyzer"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()
                    .onDrop(of: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .fileURL], isTargeted: nil) { providers in
                        handleDrop(providers: providers)
                    }

                // Content
                contentView
            }
            .navigationTitle(navigationTitleText)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if case .analyzing = viewModel.state {
                        Button("Cancel") {
                            viewModel.cancelAnalysis()
                        }
                    } else if case .finished = viewModel.state {
                        Button("New Analysis") {
                            viewModel.reset()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 500)
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .idle:
            idleView

        case .loadingMetadata:
            loadingMetadataView

        case .analyzing(let progress):
            analyzingView(progress: progress)

        case .finished(let packets, let metadata):
            finishedView(packets: packets, metadata: metadata)

        case .failed(let message):
            failedView(message: message)
        }
    }

    // MARK: - State Views

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "film")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            Text("Select a Video File to Analyze")
                .font(.title2)
                .fontWeight(.medium)

            Text("This app will read compressed video packets and visualize their sizes over time.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            Button(action: openFile) {
                Label("Open Video File", systemImage: "folder")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("or drag and drop a video file here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .padding()
    }

    private var loadingMetadataView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading video metadata...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .padding()
    }

    private func analyzingView(progress: Double) -> some View {
        VStack(spacing: 20) {
            ProgressView(value: progress) {
                Text("Analyzing video packets...")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .progressViewStyle(.linear)
            .frame(width: 400)

            if let url = viewModel.selectedFileURL {
                Text("File: \(url.lastPathComponent)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Cancel") {
                viewModel.cancelAnalysis()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .padding()
    }

    private func finishedView(packets: [PacketSample], metadata: VideoMetadata) -> some View {
        PacketChartView(packets: packets, metadata: metadata)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("Analysis Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            Button("Try Another File") {
                viewModel.reset()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .padding()
    }

    // MARK: - File Selection

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Select a video file to analyze"

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            viewModel.analyzeFile(at: url)
        }
    }

    // MARK: - Drag and Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard viewModel.canSelectFile else {
            return false
        }

        guard let provider = providers.first else {
            return false
        }

        // Debug: Print available type identifiers
        print("Available type identifiers: \(provider.registeredTypeIdentifiers)")

        // Get the first registered type identifier (usually the most specific)
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first else {
            print("No type identifiers available")
            return false
        }

        print("Using type identifier: \(typeIdentifier)")

        // Load in-place file representation (accesses original file, no copying)
        provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, isInPlace, error in
            if let error = error {
                print("Error loading in-place file: \(error.localizedDescription)")
                return
            }

            guard let fileURL = url else {
                print("No URL provided")
                return
            }

            print("Loaded file URL (in-place: \(isInPlace)): \(fileURL)")

            // Start accessing the security-scoped resource
            let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
            print("Started accessing security-scoped resource: \(didStartAccessing)")

            // Process the file at its original location
            self.processDroppedFile(fileURL)

            // Note: We should stop accessing when done, but since analysis is async,
            // we'll keep access for the duration of the app session
        }

        return true
    }

    private func processDroppedFile(_ url: URL) {
        // Check if it's a video file
        let pathExtension = url.pathExtension.lowercased()
        let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "mpeg", "mpg", "wmv", "flv", "webm", "3gp", "ts", "mts", "m2ts"]

        print("Dropped file: \(url.path) (extension: \(pathExtension))")

        if videoExtensions.contains(pathExtension) {
            DispatchQueue.main.async {
                self.viewModel.analyzeFile(at: url)
            }
        } else {
            print("File is not a supported video format: \(pathExtension)")
        }
    }
}

// MARK: - Preview

#Preview {
    MainView()
}
