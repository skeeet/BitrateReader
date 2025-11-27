//
//  PacketChartView.swift
//  BitrateReader
//
//  Created by skeeet on 11/27/25.
//

import SwiftUI
import Charts
import CoreMedia

/// View for displaying packet size data as a chart
struct PacketChartView: View {

    let packets: [PacketSample]
    let metadata: VideoMetadata

    @State private var showKeyframes: Bool = true
    @State private var zoomLevel: Double = 1.0  // 1.0 = full view, higher = zoomed in
    @State private var panOffset: Double = 0.0  // 0.0 to 1.0, position in timeline
    @State private var selectedTime: Double? = nil  // Currently hovered time position

    // Debouncing for smooth pan/zoom
    @State private var debouncedZoom: Double = 1.0
    @State private var debouncedPan: Double = 0.0
    @State private var debounceTask: Task<Void, Never>?

    // Cached statistics (computed once during init)
    private let cachedMinSize: Int64
    private let cachedMaxSize: Int64
    private let cachedAvgSize: Int64
    private let cachedAvgBitrate: Int64

    init(packets: [PacketSample], metadata: VideoMetadata) {
        self.packets = packets
        self.metadata = metadata

        // Pre-compute statistics once - filter out invalid packets (no time or zero size)
        let valid = packets.filter { $0.timeInSeconds != nil && $0.sizeBytes > 0 }
        if !valid.isEmpty {
            cachedMinSize = valid.map(\.sizeBytes).min() ?? 0
            cachedMaxSize = valid.map(\.sizeBytes).max() ?? 0

            let total = valid.reduce(Int64(0)) { $0 + $1.sizeBytes }
            cachedAvgSize = total / Int64(valid.count)

            if metadata.durationSeconds > 0 {
                let totalBits = total * 8
                cachedAvgBitrate = Int64(Double(totalBits) / metadata.durationSeconds)
            } else {
                cachedAvgBitrate = 0
            }
        } else {
            cachedMinSize = 0
            cachedMaxSize = 0
            cachedAvgSize = 0
            cachedAvgBitrate = 0
        }
    }

    // MARK: - Computed Properties

    /// Filter out invalid packets and prepare for display
    private var validPackets: [PacketSample] {
        packets.filter { $0.timeInSeconds != nil && $0.sizeBytes > 0 }
    }

    /// Calculate visible time range based on zoom and pan (uses debounced values)
    private var visibleTimeRange: ClosedRange<Double> {
        let allTimes = validPackets.compactMap { $0.timeInSeconds }
        guard !allTimes.isEmpty,
              let fullMin = allTimes.min(),
              let fullMax = allTimes.max() else {
            return 0...1
        }

        let totalDuration = fullMax - fullMin
        let visibleDuration = totalDuration / debouncedZoom

        // Calculate start position based on pan offset
        let maxPanOffset = max(0, totalDuration - visibleDuration)
        let startTime = fullMin + (maxPanOffset * debouncedPan)
        let endTime = min(fullMax, startTime + visibleDuration)

        return startTime...endTime
    }

    /// Debounce zoom/pan updates to avoid expensive recalculations
    private func updateDebounced() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            if !Task.isCancelled {
                debouncedZoom = zoomLevel
                debouncedPan = panOffset
            }
        }
    }

    /// Get packets within visible time range and downsample intelligently
    private var displayPackets: [PacketSample] {
        let visibleRange = visibleTimeRange

        // Filter to visible packets and sort by presentation time
        let visiblePackets = validPackets
            .filter { packet in
                guard let time = packet.timeInSeconds else { return false }
                return visibleRange.contains(time)
            }
            .sorted { packet1, packet2 in
                guard let time1 = packet1.timeInSeconds,
                      let time2 = packet2.timeInSeconds else {
                    return false
                }
                return time1 < time2
            }

        // Smart downsampling based on chart width (assume ~800px width)
        let chartWidth = 800.0
        let pixelsPerPacket = chartWidth / Double(visiblePackets.count)

        // If more than 2 packets per pixel, aggregate into buckets
        if pixelsPerPacket < 0.5 {
            return aggregateIntoBuckets(visiblePackets, targetBuckets: Int(chartWidth))
        }

        return visiblePackets
    }

    private var maxPacketSize: Int64 {
        cachedMaxSize
    }

    private var minPacketSize: Int64 {
        cachedMinSize
    }

    private var averagePacketSize: Int64 {
        cachedAvgSize
    }

    /// Calculate average bitrate in bits per second
    private var averageBitrate: Int64 {
        cachedAvgBitrate
    }

    /// Format bitrate for display (Mbps or Kbps)
    private var bitrateString: String {
        let bitrate = averageBitrate
        if bitrate >= 1_000_000 {
            return String(format: "%.2f Mbps", Double(bitrate) / 1_000_000.0)
        } else if bitrate >= 1_000 {
            return String(format: "%.1f Kbps", Double(bitrate) / 1_000.0)
        } else {
            return "\(bitrate) bps"
        }
    }

    /// Find the nearest packet to the selected time
    private var selectedPacket: PacketSample? {
        guard let time = selectedTime else { return nil }

        return displayPackets.min(by: { packet1, packet2 in
            guard let time1 = packet1.timeInSeconds,
                  let time2 = packet2.timeInSeconds else {
                return false
            }
            return abs(time1 - time) < abs(time2 - time)
        })
    }

    private var timeRange: ClosedRange<Double> {
        return visibleTimeRange
    }

    private var sizeRange: ClosedRange<Int64> {
        guard !validPackets.isEmpty else {
            return 0...1
        }
        let minSize = minPacketSize
        let maxSize = maxPacketSize
        let range = maxSize - minSize
        // Add a small padding at the bottom (0 or min - 10%)
        let paddedMin = Swift.max(Int64(0), minSize - range / 10)
        // Add padding at the top (max + 10%)
        let paddedMax = maxSize + range / 10
        return paddedMin...paddedMax
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation controls
            VStack(alignment: .leading, spacing: 8) {
                zoomControlsSection
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // Chart (takes all available space, min 200px)
            chartSection
                .frame(minHeight: 200, maxHeight: .infinity)
                .padding()

            Divider()

            // Stats and codec info
            VStack(alignment: .leading, spacing: 12) {
                // Metadata (codec, duration, etc)
                metadataSection

                Divider()

                // Statistics
                statisticsSection
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
    }

    // MARK: - Subviews

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let filePath = metadata.filePath {
                Text("File: \(filePath)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 20) {
                if let codec = metadata.codecDescription {
                    Text("Codec: \(codec)")
                }
                Text("Bitrate: \(bitrateString)")
                Text("Duration: \(formatDuration(metadata.durationSeconds))")
                Text("Packets: \(packets.count)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private var zoomControlsSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Zoom label
                Text("Zoom:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Zoom out button
                Button(action: {
                    zoomLevel = max(1.0, zoomLevel / 2.0)
                    // Reset pan when zooming out to full view
                    if zoomLevel == 1.0 {
                        panOffset = 0.0
                    }
                    updateDebounced()
                }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(zoomLevel <= 1.0)

                // Zoom level display
                Text(String(format: "%.1fx", zoomLevel))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40)

                // Zoom in button
                Button(action: {
                    zoomLevel = min(100.0, zoomLevel * 2.0)
                    updateDebounced()
                }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Reset button
                Button(action: {
                    zoomLevel = 1.0
                    panOffset = 0.0
                    debouncedZoom = 1.0
                    debouncedPan = 0.0
                }) {
                    Text("Reset")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(zoomLevel == 1.0 && panOffset == 0.0)

                Spacer()

                // Show packet count info
                Text("\(displayPackets.count) points displayed")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Keyframe toggle
                Toggle(isOn: $showKeyframes) {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                            .font(.caption)
                        Text("Keyframes")
                            .font(.caption)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // Pan slider (only show when zoomed in)
            if zoomLevel > 1.0 {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Slider(value: $panOffset, in: 0...1)
                        .controlSize(.small)
                        .onChange(of: panOffset) {
                            updateDebounced()
                        }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var chartSection: some View {
        Chart {
            // Draw packet size line
            ForEach(displayPackets) { packet in
                if let timeSeconds = packet.timeInSeconds {
                    LineMark(
                        x: .value("Time", timeSeconds),
                        y: .value("Size", packet.sizeBytes)
                    )
                    .foregroundStyle(Color.blue.gradient)
                    .interpolationMethod(.linear)
                }
            }

            // Draw keyframe markers (if enabled)
            if showKeyframes {
                ForEach(displayPackets.filter { $0.isKeyframe }) { packet in
                    if let timeSeconds = packet.timeInSeconds {
                        // Vertical line for keyframe
                        RuleMark(
                            x: .value("Keyframe", timeSeconds)
                        )
                        .foregroundStyle(Color.red.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .annotation(position: .top, alignment: .center) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.red.opacity(0.6))
                        }

                        // Highlight point for keyframe
                        PointMark(
                            x: .value("Time", timeSeconds),
                            y: .value("Size", packet.sizeBytes)
                        )
                        .foregroundStyle(Color.red)
                        .symbolSize(30)
                    }
                }
            }

            // Show selected packet on hover
            if let packet = selectedPacket, let timeSeconds = packet.timeInSeconds {
                // Vertical line at cursor
                RuleMark(x: .value("Selected", timeSeconds))
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Packet #\(packet.index)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                            Text("Time: \(formatTime(timeSeconds))")
                                .font(.caption2)
                            Text("Size: \(formatBytes(packet.sizeBytes))")
                                .font(.caption2)
                            if packet.isKeyframe {
                                HStack(spacing: 2) {
                                    Image(systemName: "key.fill")
                                        .font(.system(size: 8))
                                    Text("Keyframe")
                                }
                                .font(.caption2)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(6)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
                        .cornerRadius(6)
                        .shadow(radius: 4)
                    }

                // Highlight point at cursor
                PointMark(
                    x: .value("Time", timeSeconds),
                    y: .value("Size", packet.sizeBytes)
                )
                .foregroundStyle(Color.green)
                .symbolSize(50)
            }
        }
        .chartXSelection(value: $selectedTime)
        .chartXScale(domain: timeRange)
        .chartYScale(domain: sizeRange)
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(formatTime(seconds))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let bytes = value.as(Int64.self) {
                        Text(formatBytes(bytes))
                    }
                }
            }
        }
        .chartXAxisLabel("Time")
        .chartYAxisLabel("Packet Size")
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statistics")
                .font(.headline)

            HStack(spacing: 30) {
                statisticItem(label: "Min Size", value: formatBytes(minPacketSize))
                statisticItem(label: "Max Size", value: formatBytes(maxPacketSize))
                statisticItem(label: "Average Size", value: formatBytes(averagePacketSize))

                let keyframeCount = validPackets.filter(\.isKeyframe).count
                let keyframePercent = validPackets.isEmpty ? 0 : (Double(keyframeCount) / Double(validPackets.count) * 100.0)
                statisticItem(
                    label: "Keyframes",
                    value: "\(keyframeCount) (\(String(format: "%.1f%%", keyframePercent)))"
                )
            }
            .font(.caption)
        }
    }

    private func statisticItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .foregroundColor(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    // MARK: - Helper Methods

    /// Safely converts Double to Int, returning nil if out of range
    private func safeIntConversion(_ value: Double) -> Int? {
        guard value.isFinite && value >= Double(Int.min) && value <= Double(Int.max) else {
            return nil
        }
        return Int(value)
    }

    private func downsample(packets: [PacketSample], targetCount: Int) -> [PacketSample] {
        guard packets.count > targetCount else { return packets }

        let stride = packets.count / targetCount
        return packets.enumerated()
            .filter { $0.offset % stride == 0 }
            .map { $0.element }
    }

    /// Aggregates packets into time-based buckets, keeping the max size in each bucket
    /// This prevents rendering thousands of points when zoomed out
    private func aggregateIntoBuckets(_ packets: [PacketSample], targetBuckets: Int) -> [PacketSample] {
        guard packets.count > targetBuckets, !packets.isEmpty else { return packets }

        // Get time range
        let times = packets.compactMap { $0.timeInSeconds }
        guard let minTime = times.min(), let maxTime = times.max() else { return packets }

        let timeRange = maxTime - minTime
        let bucketDuration = timeRange / Double(targetBuckets)

        // Use dictionary for sparse bucketing (more memory efficient)
        var buckets: [Int: PacketSample] = [:]
        buckets.reserveCapacity(targetBuckets)

        // For each packet, keep only the max in each bucket
        for packet in packets {
            guard let time = packet.timeInSeconds else { continue }
            let bucketIndex = min(Int((time - minTime) / bucketDuration), targetBuckets - 1)

            // Keep the packet with max size in this bucket
            if let existing = buckets[bucketIndex] {
                if packet.sizeBytes > existing.sizeBytes {
                    buckets[bucketIndex] = packet
                }
            } else {
                buckets[bucketIndex] = packet
            }
        }

        // Extract and sort by presentation time
        return buckets.values.sorted { packet1, packet2 in
            guard let time1 = packet1.timeInSeconds,
                  let time2 = packet2.timeInSeconds else {
                return false
            }
            return time1 < time2
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard let secondsInt = safeIntConversion(seconds) else {
            return "N/A"
        }
        let minutes = secondsInt / 60
        let secs = secondsInt % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard let secondsInt = safeIntConversion(seconds) else {
            return "N/A"
        }
        let hours = secondsInt / 3600
        let minutes = secondsInt / 60 % 60
        let secs = secondsInt % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Preview

#Preview {
    let samplePackets = (0..<100).map { i in
        let time = CMTime(value: Int64(i * 33), timescale: 1000) // 33ms per frame
        // Make every 30th frame a keyframe (simulating GOP structure)
        let isKeyframe = i % 30 == 0
        return PacketSample(
            index: i,
            presentationTime: time,
            sizeBytes: isKeyframe ? Int64.random(in: 30000...50000) : Int64.random(in: 5000...15000),
            isKeyframe: isKeyframe
        )
    }

    let sampleMetadata = VideoMetadata(
        durationSeconds: 3.3,
        frameCountEstimate: 100,
        codecDescription: "avc1",
        fileName: "sample.mp4",
        filePath: "/Users/example/Videos/sample.mp4",
        fileSizeBytes: 1024000
    )

    return PacketChartView(packets: samplePackets, metadata: sampleMetadata)
        .frame(width: 800, height: 600)
}
