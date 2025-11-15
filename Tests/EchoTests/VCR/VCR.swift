// VCR.swift
// Echo Tests - VCR Infrastructure
// Global VCR coordinator for managing record/playback mode

import Foundation
@testable import Echo

/// Global VCR coordinator
public actor VCR {
    /// Singleton instance
    public static let shared = VCR()

    /// Current cassette being recorded/played
    private var currentCassette: VCRCassette?

    /// VCR mode
    public enum Mode {
        /// Record new interactions (hits real API)
        case record

        /// Playback recorded interactions (no network calls)
        case playback

        /// Auto: playback if cassette exists, otherwise record
        case auto
    }

    /// Current mode
    private var mode: Mode = .playback

    /// Directory for storing cassettes
    private var cassettesDirectory: URL

    private init() {
        // Default to Tests/Fixtures/Cassettes
        let testBundle = Bundle(for: TestBundleMarker.self)
        let testsDir = testBundle.bundleURL.deletingLastPathComponent()
        self.cassettesDirectory = testsDir
            .appendingPathComponent("EchoTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Cassettes")

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: cassettesDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Insert a cassette for recording/playback
    /// - Parameters:
    ///   - name: Cassette name
    ///   - mode: VCR mode (record/playback/auto)
    public func insertCassette(_ name: String, mode: Mode = .playback) throws {
        self.mode = mode

        switch mode {
        case .record:
            // Start fresh cassette for recording
            currentCassette = VCRCassette(name: name, interactions: [])

        case .playback:
            // Load existing cassette
            currentCassette = try VCRCassette.load(name: name, from: cassettesDirectory)

        case .auto:
            // Try to load, fall back to record mode
            do {
                currentCassette = try VCRCassette.load(name: name, from: cassettesDirectory)
                self.mode = .playback
            } catch {
                currentCassette = VCRCassette(name: name, interactions: [])
                self.mode = .record
            }
        }
    }

    /// Eject current cassette (save if recording)
    public func ejectCassette() throws {
        guard var cassette = currentCassette else { return }

        if mode == .record {
            // Save recorded interactions
            try cassette.save(to: cassettesDirectory)
        }

        currentCassette = nil
    }

    /// Get current cassette
    public func getCassette() -> VCRCassette? {
        return currentCassette
    }

    /// Check if currently in record mode
    public func isRecording() -> Bool {
        return mode == .record
    }

    /// Record an interaction (used by recorder)
    public func record(_ interaction: VCRInteraction) {
        currentCassette?.record(interaction)
    }

    /// Set cassettes directory
    public func setCassettesDirectory(_ url: URL) {
        self.cassettesDirectory = url
        try? FileManager.default.createDirectory(
            at: cassettesDirectory,
            withIntermediateDirectories: true
        )
    }
}

/// Marker class for getting test bundle
private class TestBundleMarker {}

/// Convenience functions for test usage
extension VCR {
    /// Use a cassette for the duration of a test
    /// - Parameters:
    ///   - name: Cassette name
    ///   - mode: VCR mode
    ///   - test: Test block to execute
    public func useCassette<T>(
        _ name: String,
        mode: Mode = .playback,
        _ test: () async throws -> T
    ) async throws -> T {
        try insertCassette(name, mode: mode)
        defer {
            Task {
                try? await ejectCassette()
            }
        }
        return try await test()
    }
}
