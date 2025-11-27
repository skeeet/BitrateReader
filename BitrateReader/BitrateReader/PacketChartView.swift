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

    // MARK: - Static Constants

    // Shared formatter for thread safety and performance - ByteCountFormatter is expensive to create
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        return formatter
    }()

    // MARK: - Properties

    let packets: [PacketSample]
    let metadata: VideoMetadata

    @State private var showKeyframes: Bool = true
    @State private var hideKeyframePackets: Bool = false
    @State private var zoomLevel: Double = 1.0
    @State private var panOffset: Double = 0.0
    @State private var selectedTime: Double? = nil

    @State private var debouncedZoom: Double = 1.0
    @State private var debouncedPan: Double = 0.0
    @State private var debounceTask: Task<Void, Never>?

    // Cached to avoid recomputing on every UI update - only changes when zoom/pan changes
    @State private var cachedDisplayPackets: [PacketSample] = []

    // Pre-computed statistics to avoid O(n) recalculation on every render
    private let cachedMinSize: Int64
    private let cachedMaxSize: Int64
    private let cachedAvgSize: Int64
    private let cachedAvgBitrate: Int64
    private let cachedKeyframeCount: Int
    private let cachedKeyframePercent: Double

    // ProRes/DNxHD have every frame as keyframe - rendering all is slow and meaningless
    private let isAllIntraCodec: Bool

    // GOP (Group of Pictures) analysis - only meaningful for inter-frame codecs
    private let gopCount: Int
    private let gopAvgSize: Double
    private let gopMinSize: Int
    private let gopMaxSize: Int

    init(packets: [PacketSample], metadata: VideoMetadata) {
        self.packets = packets
        self.metadata = metadata

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

            cachedKeyframeCount = valid.filter(\.isKeyframe).count
            cachedKeyframePercent = Double(cachedKeyframeCount) / Double(valid.count) * 100.0

            // >90% threshold accounts for potential decoding artifacts while catching ProRes/DNxHD
            isAllIntraCodec = cachedKeyframePercent > 90.0

            // Analyze GOP structure for inter-frame codecs
            if !isAllIntraCodec && cachedKeyframeCount > 1 {
                let keyframeIndices = valid.enumerated()
                    .filter { $0.element.isKeyframe }
                    .map { $0.offset }

                var gopSizes: [Int] = []
                for i in 0..<(keyframeIndices.count - 1) {
                    let gopSize = keyframeIndices[i + 1] - keyframeIndices[i]
                    gopSizes.append(gopSize)
                }

                if !gopSizes.isEmpty {
                    gopCount = gopSizes.count
                    gopMinSize = gopSizes.min() ?? 0
                    gopMaxSize = gopSizes.max() ?? 0
                    gopAvgSize = Double(gopSizes.reduce(0, +)) / Double(gopSizes.count)
                } else {
                    gopCount = 0
                    gopMinSize = 0
                    gopMaxSize = 0
                    gopAvgSize = 0
                }
            } else {
                gopCount = 0
                gopMinSize = 0
                gopMaxSize = 0
                gopAvgSize = 0
            }
        } else {
            cachedMinSize = 0
            cachedMaxSize = 0
            cachedAvgSize = 0
            cachedAvgBitrate = 0
            cachedKeyframeCount = 0
            cachedKeyframePercent = 0
            isAllIntraCodec = false
            gopCount = 0
            gopMinSize = 0
            gopMaxSize = 0
            gopAvgSize = 0
        }
    }

    // MARK: - Computed Properties

    private var validPackets: [PacketSample] {
        packets.filter { $0.timeInSeconds != nil && $0.sizeBytes > 0 }
    }

    private var visibleTimeRange: ClosedRange<Double> {
        let allTimes = validPackets.compactMap { $0.timeInSeconds }
        guard !allTimes.isEmpty,
              let fullMin = allTimes.min(),
              let fullMax = allTimes.max() else {
            return 0...1
        }

        let totalDuration = fullMax - fullMin
        let visibleDuration = totalDuration / debouncedZoom
        let maxPanOffset = max(0, totalDuration - visibleDuration)
        let startTime = fullMin + (maxPanOffset * debouncedPan)
        let endTime = min(fullMax, startTime + visibleDuration)

        return startTime...endTime
    }

    private func updateDebounced() {
        // Capture current values to avoid race condition if state changes during Task execution
        let currentZoom = zoomLevel
        let currentPan = panOffset

        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            if !Task.isCancelled {
                debouncedZoom = currentZoom
                debouncedPan = currentPan
            }
        }
    }

    private var displayPackets: [PacketSample] {
        cachedDisplayPackets
    }

    private func computeDisplayPackets() -> [PacketSample] {
        let visibleRange = visibleTimeRange

        let visiblePackets = validPackets
            .filter { packet in
                guard let time = packet.timeInSeconds else { return false }

                // Filter out keyframes if requested (useful for analyzing P/B-frame patterns)
                if hideKeyframePackets && packet.isKeyframe {
                    return false
                }

                return visibleRange.contains(time)
            }
            .sorted { packet1, packet2 in
                guard let time1 = packet1.timeInSeconds,
                      let time2 = packet2.timeInSeconds else {
                    return false
                }
                return time1 < time2
            }

        let chartWidth = 800.0
        let pixelsPerPacket = chartWidth / Double(visiblePackets.count)

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

    private var averageBitrate: Int64 {
        cachedAvgBitrate
    }

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
        let paddedMin = Swift.max(Int64(0), minSize - range / 10)
        let paddedMax = maxSize + range / 10
        return paddedMin...paddedMax
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                zoomControlsSection
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            chartSection
                .frame(minHeight: 200, maxHeight: .infinity)
                .padding()

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                metadataSection
                Divider()
                statisticsSection
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
        .onAppear {
            cachedDisplayPackets = computeDisplayPackets()
        }
        .onChange(of: debouncedZoom) {
            cachedDisplayPackets = computeDisplayPackets()
        }
        .onChange(of: debouncedPan) {
            cachedDisplayPackets = computeDisplayPackets()
        }
        .onChange(of: hideKeyframePackets) {
            cachedDisplayPackets = computeDisplayPackets()
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
                Text("Zoom:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: {
                    zoomLevel = max(1.0, zoomLevel / 2.0)
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

                Text(String(format: "%.1fx", zoomLevel))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40)

                Button(action: {
                    zoomLevel = min(100.0, zoomLevel * 2.0)
                    updateDebounced()
                }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

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

                Text("\(displayPackets.count) points displayed")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isAllIntraCodec {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("All frames are keyframes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Toggle(isOn: $showKeyframes) {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                                .font(.caption)
                            Text("Keyframe Markers")
                                .font(.caption)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Toggle(isOn: $hideKeyframePackets) {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.slash")
                                .font(.caption)
                            Text("Hide I-Frames")
                                .font(.caption)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

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
        // Only show keyframe markers if markers are enabled, not all-intra, and we're not hiding keyframes
        let keyframePackets = (showKeyframes && !isAllIntraCodec && !hideKeyframePackets) ? displayPackets.filter { $0.isKeyframe } : []

        return Chart {
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

            if showKeyframes && !isAllIntraCodec && !hideKeyframePackets {
                ForEach(keyframePackets) { packet in
                    if let timeSeconds = packet.timeInSeconds {
                        RuleMark(
                            x: .value("Keyframe", timeSeconds)
                        )
                        .foregroundStyle(Color.red.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                        PointMark(
                            x: .value("Time", timeSeconds),
                            y: .value("Size", packet.sizeBytes)
                        )
                        .foregroundStyle(Color.red)
                        .symbolSize(30)
                    }
                }
            }

            if let packet = selectedPacket, let timeSeconds = packet.timeInSeconds {
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
                statisticItem(
                    label: "Keyframes",
                    value: "\(cachedKeyframeCount) (\(String(format: "%.1f%%", cachedKeyframePercent)))"
                )
            }
            .font(.caption)

            // GOP structure info - only for inter-frame codecs
            if !isAllIntraCodec && gopCount > 0 {
                Divider()
                    .padding(.vertical, 4)

                Text("GOP Structure")
                    .font(.headline)

                HStack(spacing: 30) {
                    statisticItem(label: "GOP Count", value: "\(gopCount)")
                    statisticItem(label: "Avg GOP Size", value: String(format: "%.1f frames", gopAvgSize))
                    statisticItem(label: "Min GOP", value: "\(gopMinSize) frames")
                    statisticItem(label: "Max GOP", value: "\(gopMaxSize) frames")

                    if gopMinSize == gopMaxSize {
                        statisticItem(label: "Pattern", value: "Fixed (\(gopMinSize))")
                    } else {
                        let variance = gopMaxSize - gopMinSize
                        if variance <= 2 {
                            statisticItem(label: "Pattern", value: "Mostly Fixed")
                        } else {
                            statisticItem(label: "Pattern", value: "Variable")
                        }
                    }
                }
                .font(.caption)
            }
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

    // Aggregate packets into time buckets to reduce rendering overhead
    // Strategy: keep the largest packet in each bucket to preserve bitrate spikes
    private func aggregateIntoBuckets(_ packets: [PacketSample], targetBuckets: Int) -> [PacketSample] {
        guard packets.count > targetBuckets, !packets.isEmpty else { return packets }

        let times = packets.compactMap { $0.timeInSeconds }
        guard let minTime = times.min(), let maxTime = times.max() else { return packets }

        let timeRange = maxTime - minTime
        let bucketDuration = timeRange / Double(targetBuckets)

        // Dictionary allows sparse bucketing - memory efficient for zoomed views
        var buckets: [Int: PacketSample] = [:]
        buckets.reserveCapacity(targetBuckets)

        for packet in packets {
            guard let time = packet.timeInSeconds else { continue }

            let normalizedTime = time - minTime
            guard normalizedTime >= 0, bucketDuration > 0 else { continue }

            let rawIndex = normalizedTime / bucketDuration

            // Defensive check: division by very small numbers can produce non-finite results
            guard rawIndex.isFinite else { continue }

            let bucketIndex: Int
            if rawIndex < 0 {
                bucketIndex = 0
            } else if rawIndex >= Double(targetBuckets) {
                bucketIndex = targetBuckets - 1
            } else {
                bucketIndex = Int(rawIndex)
            }

            // Keep largest packet per bucket to show worst-case bitrate
            if let existing = buckets[bucketIndex] {
                if packet.sizeBytes > existing.sizeBytes {
                    buckets[bucketIndex] = packet
                }
            } else {
                buckets[bucketIndex] = packet
            }
        }

        return buckets.values.sorted { packet1, packet2 in
            guard let time1 = packet1.timeInSeconds,
                  let time2 = packet2.timeInSeconds else {
                return false
            }
            return time1 < time2
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        Self.byteFormatter.string(fromByteCount: bytes)
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
        let time = CMTime(value: Int64(i * 33), timescale: 1000)
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
