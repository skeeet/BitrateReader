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


### Building for Release

```bash
xcodebuild -project BitrateReader.xcodeproj \
           -scheme BitrateReader \
           -configuration Release \
           clean build
```

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
