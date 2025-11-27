# BitrateReader

A native macOS application for analyzing compressed video packet sizes without decoding. Built with Swift and SwiftUI.

![macOS](https://img.shields.io/badge/macOS-15.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## Overview

BitrateReader provides real-time visualization of compressed video packet sizes over time, helping video engineers, codec developers, and content creators understand bitrate characteristics at the packet level.

**Key Features:**
- 📊 Interactive packet size visualization
- 🎯 Keyframe/I-frame detection and marking
- 🔍 Zoom and pan navigation
- 📈 Detailed statistics (min/max/avg packet sizes)
- 🚀 Optimized for large video files
- 💾 No decoding - analyzes compressed data directly

## Why BitrateReader?

Unlike traditional video analysis tools that decode frames, BitrateReader reads packets directly from the compressed stream using AVFoundation. This provides:

- **True packet-level analysis** - See actual encoded sizes, not estimated values
- **Minimal resource usage** - No CPU-intensive decoding
- **Fast processing** - Analyze multi-GB files in seconds
- **Codec-agnostic** - Works with any format AVFoundation supports (H.264, H.265, ProRes, VP9, etc.)

## Screenshots

<!-- Add screenshots here -->
_Screenshots coming soon_

## Features

### 🎬 Video Analysis

- **Direct Packet Reading** - Uses `AVAssetReader` with compressed output
- **Keyframe Detection** - Automatically identifies I-frames
- **PTS Sorting** - Handles files with B-frames correctly
- **Format Support** - MP4, MOV, MKV, TS, and all AVFoundation formats

### 📊 Visualization

- **Interactive Chart** - Real-time packet size graphing
- **Zoom Controls** - Up to 100x magnification
- **Pan Navigation** - Scrub through timeline
- **Hover Tooltips** - Detailed packet information on mouse-over
- **Keyframe Markers** - Visual indicators for sync frames

### 📈 Statistics

- **Minimum Packet Size** - Smallest compressed frame
- **Maximum Packet Size** - Largest compressed frame (typically I-frames)
- **Average Packet Size** - Mean packet size
- **Average Bitrate** - Calculated from total size and duration
- **Keyframe Percentage** - GOP structure analysis
- **Codec Information** - FourCC codec identifier

### ⚡ Performance

- **Smart Downsampling** - Automatic bucketing for large files
- **Cached Calculations** - Statistics computed once
- **Debounced Updates** - Smooth UI during interaction
- **Memory Efficient** - Only stores packet metadata

## Requirements

- **macOS:** 15.0 or later
- **Xcode:** 16.0+ (for building from source)
- **Architecture:** Universal (Apple Silicon and Intel)

## Installation

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/yourusername/BitrateReader.git
cd BitrateReader
```

2. Open the Xcode project:
```bash
open BitrateReader.xcodeproj
```

3. Build and run:
   - Select the `BitrateReader` scheme
   - Choose your Mac as the destination
   - Press `⌘R` to build and run

### Requirements for Building

- Xcode 16.0 or later
- macOS 15.0 SDK or later

## Usage

### Basic Workflow

1. **Launch BitrateReader**
2. **Open a video file:**
   - Click "Open Video File" button, or
   - Drag and drop a video file into the window
3. **Wait for analysis** - Progress bar shows completion
4. **Explore the data:**
   - Use zoom controls to focus on specific timeframes
   - Toggle keyframe markers on/off
   - Hover over the graph to see packet details

### Understanding the UI

**Navigation Controls** (Top)
- **Zoom In/Out** - Magnify timeline (1x to 100x)
- **Pan Slider** - Navigate when zoomed in
- **Reset** - Return to full view
- **Keyframes Toggle** - Show/hide I-frame markers

**Graph Area** (Middle)
- **Blue line** - Packet size over time
- **Red markers** - Keyframes (I-frames)
- **Green highlight** - Current hover position
- **Tooltip** - Packet index, time, size, and type

**Info Section** (Bottom)
- **File path** - Full path to video file (text selectable)
- **Codec** - Video codec identifier
- **Bitrate** - Average bitrate in Mbps/Kbps
- **Duration** - Total video length
- **Statistics** - Min/max/avg packet sizes and keyframe count

### Interpreting Results

#### Codec Characteristics

**ProRes (All-Intra)**
- 100% keyframes
- Consistent packet sizes
- High bitrate

**H.264/H.265 (Inter-frame)**
- Periodic keyframes (GOP structure)
- Variable packet sizes
- I-frames much larger than P/B-frames

**Variable Bitrate (VBR)**
- Significant size variations
- Larger packets for complex scenes
- Smaller packets for static scenes

**Constant Bitrate (CBR)**
- More uniform packet sizes
- Predictable bitrate
- Better for streaming

## Technical Details

### Architecture

```
BitrateReader/
├── BitrateReaderApp.swift          # App entry point
├── MainView.swift                   # Main UI coordinator
├── PacketChartView.swift            # Visualization + controls
├── PacketAnalysisViewModel.swift    # State management
├── VideoPacketAnalyzer.swift        # Packet extraction (Actor)
├── PacketSample.swift               # Packet data model
├── VideoMetadata.swift              # Video metadata
└── AnalysisError.swift              # Error handling
```

### Key Technologies

- **SwiftUI** - Complete UI framework
- **Swift Charts** - Native charting
- **AVFoundation** - Video packet reading
- **Swift Concurrency** - Async/await and actors
- **Swift 6** - Strict concurrency checking

### How It Works

1. **File Selection** - User picks video via dialog or drag-drop
2. **Asset Loading** - `AVURLAsset` created with security-scoped access
3. **Metadata Extraction** - Duration, codec, file size loaded
4. **Packet Reading** - `AVAssetReaderTrackOutput` with `outputSettings = nil`
5. **Size Extraction** - `CMSampleBufferGetTotalSampleSize()` for each packet
6. **Keyframe Detection** - Check `kCMSampleAttachmentKey_NotSync` attachment
7. **PTS Sorting** - Packets sorted by presentation time
8. **Visualization** - SwiftUI Charts renders interactive graph

### Performance Optimizations

**Pre-computation**
- CMTime to Double conversion done once per packet
- Statistics cached at initialization

**Smart Downsampling**
- Files >10,000 packets automatically bucketed
- Dictionary-based sparse bucketing
- Keeps maximum packet size per bucket
- Target: ~800 display points

**UI Responsiveness**
- 50ms debounce on zoom/pan updates
- Background actor for analysis
- Non-blocking progress updates

## File Format Support

BitrateReader supports any video format that AVFoundation can read:

### Tested Formats
- ✅ MP4 (H.264, H.265)
- ✅ MOV (ProRes, H.264)
- ✅ MKV (via system codecs)
- ✅ MPEG-2 Transport Stream

### Supported Codecs
- H.264 / AVC
- H.265 / HEVC
- ProRes (all variants)
- VP9
- AV1 (macOS 15+)
- MPEG-4
- And more...

## Troubleshooting

### "Analysis Failed" Error

**Possible causes:**
- Corrupted video file
- DRM-protected content
- Unsupported container format
- File permissions issue

**Solutions:**
- Try a different video file
- Check file isn't DRM-protected
- Ensure file is readable
- Grant file access permissions

### Zero Minimum Packet Size

This is now fixed in the latest version. If you still see this:
- Update to the latest build
- Ensure video file has valid compressed frames

### Slow Performance

For extremely large files:
- Analysis is optimized but depends on file size
- Chart rendering uses automatic downsampling
- Try zooming in to specific regions

## Development

### Project Structure

- **Models** - Data structures (`PacketSample`, `VideoMetadata`)
- **Services** - Business logic (`VideoPacketAnalyzer`)
- **ViewModels** - State management (`PacketAnalysisViewModel`)
- **Views** - SwiftUI UI components (`MainView`, `PacketChartView`)

### Code Style

- Swift 6 strict concurrency
- Actor isolation for thread safety
- Sendable conformance for data types
- Async/await for asynchronous operations

### Building for Release

```bash
xcodebuild -project BitrateReader.xcodeproj \
           -scheme BitrateReader \
           -configuration Release \
           clean build
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Guidelines

1. Follow existing code style
2. Maintain Swift 6 compliance
3. Add comments for complex logic
4. Test with various video formats
5. Update documentation as needed

## Roadmap

Potential future enhancements:

- [ ] Multi-track analysis (video + audio)
- [ ] Export packet data to CSV/JSON
- [ ] Batch file comparison
- [ ] GOP structure visualization
- [ ] Frame type breakdown (I/P/B analysis)
- [ ] Container-level parsing
- [ ] Custom chart themes
- [ ] Statistics export

## Known Limitations

- **No Audio Analysis** - Currently video-only
- **AVFoundation Dependency** - Limited to formats AVFoundation supports
- **macOS Only** - No iOS/iPadOS version
- **No Editing** - Analysis only, no video modification

## Credits

Built with:
- [Swift](https://swift.org) - Programming language
- [SwiftUI](https://developer.apple.com/xcode/swiftui/) - UI framework
- [Swift Charts](https://developer.apple.com/documentation/charts) - Charting framework
- [AVFoundation](https://developer.apple.com/av-foundation/) - Media framework

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Changelog

### Version 1.0 (Current)
- Initial release
- Compressed packet analysis
- Interactive visualization
- Keyframe detection
- Statistics calculation
- Zoom and pan controls
- Drag-and-drop support
- Performance optimizations
- Swift 6 compliance

---

**Questions or feedback?** Open an issue on GitHub!

**Developed with ❤️ for video engineers and codec enthusiasts**
