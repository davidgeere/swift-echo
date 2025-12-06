// Version.swift
// Echo - Version Information
//
// Semantic Versioning: MAJOR.MINOR.PATCH
// - MAJOR: Incompatible API changes
// - MINOR: Backwards-compatible functionality additions  
// - PATCH: Backwards-compatible bug fixes

import Foundation

/// Echo library version information
public enum EchoVersion {
    /// Current version of the Echo library
    public static let current = Version(major: 1, minor: 5, patch: 0)
    
    /// Version string (e.g., "1.0.0")
    public static var string: String {
        current.description
    }
    
    /// Full version string with library name
    public static var full: String {
        "Echo \(string)"
    }
    
    /// Build information
    public static let build = BuildInfo(
        date: "2025-12-06",
        commit: "main"
    )
}

/// Represents a semantic version
public struct Version: CustomStringConvertible, Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    
    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }
    
    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        if let pre = prerelease {
            return "\(base)-\(pre)"
        }
        return base
    }
    
    public static func < (lhs: Version, rhs: Version) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        
        // Pre-release versions have lower precedence
        if lhs.prerelease != nil && rhs.prerelease == nil { return true }
        if lhs.prerelease == nil && rhs.prerelease != nil { return false }
        
        // Compare pre-release versions lexically
        if let lhsPre = lhs.prerelease, let rhsPre = rhs.prerelease {
            return lhsPre < rhsPre
        }
        
        return false
    }
}

/// Build information
public struct BuildInfo: Sendable {
    public let date: String
    public let commit: String
}

// MARK: - Version History

extension EchoVersion {
    /// Version history with release notes
    public static let history: [(version: Version, date: String, notes: String)] = [
        (
            version: Version(major: 1, minor: 5, patch: 0),
            date: "2025-12-06",
            notes: """
            🎵 Audio Frequency Analysis & Level Monitoring
            
            New Features:
            • FFT-based frequency analysis for audio levels
            • AudioLevels struct with level, low, mid, high frequency bands
            • Input level monitoring (microphone) with frequency bands
            • Output level monitoring (speaker) with frequency bands
            • Observable inputLevels/outputLevels properties on Conversation
            • New events: inputLevelsChanged, outputLevelsChanged
            
            API:
            • conversation.inputLevels - Observable input audio levels
            • conversation.outputLevels - Observable output audio levels
            • AudioLevels.level - Overall RMS amplitude (0.0-1.0)
            • AudioLevels.low - Low frequency band (20-250Hz)
            • AudioLevels.mid - Mid frequency band (250-4000Hz)
            • AudioLevels.high - High frequency band (4000-20000Hz)
            
            Breaking Changes:
            • audioLevelStream now emits AudioLevels instead of Double
            • audioLevelChanged event deprecated in favor of inputLevelsChanged
            
            Technical:
            • FrequencyAnalyzer using Accelerate framework (vDSP FFT)
            • Thread-safe level analysis with OSAllocatedUnfairLock
            • Automatic smoothing for level transitions
            
            Testing:
            • New FrequencyAnalysisTests with 17 tests
            • Updated mocks for AudioLevels type
            """
        ),
        (
            version: Version(major: 1, minor: 4, patch: 0),
            date: "2025-12-06",
            notes: """
            🔊 Audio Engine Exposure for External Monitoring
            
            New Features:
            • Exposed AVAudioEngine from AudioPlayback for external audio monitoring
            • Added audioEngine property to AudioPlaybackProtocol
            • Added installAudioTap() method to Conversation and RealtimeClient
            • Added removeAudioTap() method for cleanup
            • Enables audio visualizations, level metering, and frequency analysis
            
            API:
            • AudioPlayback.audioEngine - Direct access to the underlying AVAudioEngine
            • Conversation.installAudioTap() - Safe tap installation without Sendable issues
            • Conversation.removeAudioTap() - Clean removal of installed taps
            
            Technical:
            • Uses closure-based API to safely cross actor boundaries
            • AVAudioEngine is not Sendable, so direct property access is limited
            • @preconcurrency import for AVFoundation to handle Swift 6 concurrency
            
            Testing:
            • New AudioEngineExposureTests with 7 tests
            • Tests for engine lifecycle (start/stop/nil states)
            • Tests for tap installation on mainMixerNode
            """
        ),
        (
            version: Version(major: 1, minor: 3, patch: 0),
            date: "2025-11-29",
            notes: """
            🏗️ Architecture Refactor: Event Decoupling
            
            Breaking Changes:
            • Removed all when() event handler methods from Echo and EventEmitter
            • Event observation now uses AsyncStream: for await event in echo.events { ... }
            • Added toolHandler property for custom tool handling (replaces automatic setup)
            
            New Features:
            • Pure sink EventEmitter - cleaner architecture with no internal event listeners
            • Centralized ToolExecutor actor for all tool execution
            • Internal delegate protocols for component coordination
            • Direct method calls between components (no orphaned Tasks)
            
            Memory & Resource Improvements:
            • Eliminated orphaned Task instances that could cause memory leaks
            • Proper cleanup in deinit for all AsyncStream continuations
            • No more complex cleanup requirements - components manage their own lifecycle
            • Deterministic execution flow without background Tasks for internal coordination
            
            Architecture:
            • Strict separation: internal coordination (delegates) vs external observation (stream)
            • New protocols: AudioInterruptible, ToolExecuting, RealtimeClientDelegate, TurnManagerDelegate
            • MessageQueue cleanup with deinit for continuations
            """
        ),
        (
            version: Version(major: 1, minor: 2, patch: 2),
            date: "2025-11-23",
            notes: """
            🔧 Audio Routing Fix
            
            Bug Fixes:
            • Fixed audio routing to speaker/receiver - audio now correctly routes to selected device
            • Both engines properly stop before route changes to prevent route caching
            • Route verification ensures changes take effect before restarting engines
            • Fixed AudioCapture.pause() to properly stop engine (AVAudioEngine has no pause method)
            • Improved timing and delays for route stabilization
            
            Documentation:
            • Added background audio support documentation to README
            """
        ),
        (
            version: Version(major: 1, minor: 2, patch: 1),
            date: "2025-11-23",
            notes: """
            🔧 Audio Engine Restart Fixes
            
            Bug Fixes:
            • Fixed capture engine stopping after audio output change
            • Capture engine now automatically restarts when switching devices
            • Fixed playback engine restart failures with improved error handling
            • Better audio session management to preserve engine state
            
            Debug Improvements:
            • Added comprehensive debug logging for audio diagnostics
            • Logs engine states, route changes, and restart attempts
            • All debug logs are conditional (DEBUG builds only)
            """
        ),
        (
            version: Version(major: 1, minor: 2, patch: 0),
            date: "2025-11-23",
            notes: """
            🔊 Audio Output Device Selection
            
            Breaking Changes:
            • Replaced setSpeakerRouting(useSpeaker: Bool) with setAudioOutput(device: AudioOutputDeviceType)
            • Removed speakerRouting and isBluetoothConnected properties
            • New device-based API provides better control and flexibility
            
            New Features:
            • AudioOutputDeviceType enum with builtInSpeaker, builtInReceiver, bluetooth, wiredHeadphones, systemDefault
            • availableAudioOutputDevices property to list all connected devices
            • currentAudioOutput property to check active output device
            • audioOutputChanged event when device changes
            • Automatic route change detection and event emission
            
            Improvements:
            • Better device type detection with device names
            • Support for multiple Bluetooth devices
            • More intuitive API for audio routing control
            • Comprehensive test coverage (13 new tests)
            """
        ),
        (
            version: Version(major: 1, minor: 1, patch: 0),
            date: "2025-11-23",
            notes: """
            🎯 All Events Handler & Stream
            
            New Features:
            • Listen to all events: echo.when { event in ... }
            • Async stream: for await event in echo.events { ... }
            • Sequential event processing with break support
            • Automatic handler cleanup on deallocation
            
            Memory Safety:
            • Handlers automatically cleaned up to prevent leaks
            • Proper deinit cleanup in EventEmitter
            
            Testing:
            • 5 new comprehensive tests for all-events functionality
            • Full coverage of handler and stream patterns
            """
        ),
        (
            version: Version(major: 1, minor: 0, patch: 2),
            date: "2025-11-23",
            notes: """
            📚 Enhanced Event System
            
            Event Features:
            • Multiple event listeners with array syntax: echo.when([.event1, .event2])
            • Multiple event listeners with variadic syntax: echo.when(.event1, .event2)
            • Comprehensive event documentation (EVENTS.md)
            • Complete test coverage for event system
            
            Documentation:
            • Added EVENTS.md with complete event reference
            • Examples for all 25 event types
            • Usage patterns and best practices
            """
        ),
        (
            version: Version(major: 1, minor: 0, patch: 1),
            date: "2025-11-23",
            notes: """
            🔊 Dynamic Speaker Routing
            
            Audio Features:
            • Runtime control of audio output routing
            • Switch between speaker and earpiece at any time
            • Proper Bluetooth device handling
            • Consistent API pattern with setMuted()
            """
        ),
        (
            version: Version(major: 1, minor: 0, patch: 0),
            date: "2024-11-15",
            notes: """
            🚀 Initial Release
            
            Core Features:
            • Unified API for Realtime (voice) and Responses (text) APIs
            • Seamless mode switching with context preservation
            • Message queue architecture for proper sequencing
            • Event-driven system with expressive syntax
            
            Voice Features:
            • Real-time voice conversations via WebSocket
            • Voice Activity Detection (automatic/manual/disabled)
            • Audio level monitoring for UI animations
            • Automatic transcription of all interactions
            
            Text Features:
            • Traditional text conversations with streaming
            • Server-Sent Events (SSE) support
            • Full context preservation
            
            Embeddings API:
            • Single and batch embedding generation
            • Semantic similarity search
            • Multiple model support with dimension control
            
            Structured Output:
            • Type-safe JSON generation
            • Codable schema support
            • Complex nested structures
            
            Tool Calling:
            • Function calling for both APIs
            • Automatic tool execution
            • MCP server support
            
            Technical:
            • Swift 6.0 with strict concurrency
            • Actor-based architecture
            • AsyncStream for data flow
            • @Observable for SwiftUI
            • iOS 18+ / macOS 14+
            """
        )
    ]
}

// MARK: - Version Checking

extension Echo {
    /// Current Echo version
    public static var version: String {
        EchoVersion.string
    }
    
    /// Check if library meets minimum version requirement
    public static func meetsMinimumVersion(_ required: String) -> Bool {
        guard let requiredVersion = parseVersion(required) else { return false }
        return EchoVersion.current >= requiredVersion
    }
    
    private static func parseVersion(_ string: String) -> Version? {
        let components = string.split(separator: ".")
        guard components.count >= 2 else { return nil }
        
        let major = Int(components[0]) ?? 0
        let minor = Int(components[1]) ?? 0
        let patch = components.count > 2 ? (Int(components[2]) ?? 0) : 0
        
        return Version(major: major, minor: minor, patch: patch)
    }
}