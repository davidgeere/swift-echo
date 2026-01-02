// AudioSessionManager.swift
// Echo - Audio
// Centralized audio session management for both WebRTC and WebSocket transports

@preconcurrency import AVFoundation
import Foundation

/// Centralized manager for AVAudioSession interactions
///
/// This actor provides a single source of truth for audio session state,
/// ensuring consistent behavior across WebRTC and WebSocket transports.
///
/// Key responsibilities:
/// - Configure audio session for voice chat
/// - Track current audio output device (computed from actual system state)
/// - Observe and emit route change notifications
/// - Provide available audio output devices
public actor AudioSessionManager {
    // MARK: - Singleton
    
    /// Shared singleton instance
    public static let shared = AudioSessionManager()
    
    // MARK: - Route Change Stream
    
    /// Stream of audio output device changes
    ///
    /// Subscribe to this stream to receive notifications when the audio route changes,
    /// whether triggered by user action or system events (e.g., Bluetooth connect/disconnect).
    public let routeChangeStream: AsyncStream<AudioOutputDeviceType>
    private let routeChangeContinuation: AsyncStream<AudioOutputDeviceType>.Continuation
    
    // MARK: - State
    
    /// Whether route change observation is active
    private var isObserving = false
    
    /// Observer token for route change notifications
    #if os(iOS)
    private var routeChangeObserver: NSObjectProtocol?
    #endif
    
    /// Whether the audio session is currently configured
    private var isConfigured = false
    
    // MARK: - Initialization
    
    private init() {
        var continuation: AsyncStream<AudioOutputDeviceType>.Continuation?
        self.routeChangeStream = AsyncStream { cont in
            continuation = cont
        }
        guard let unwrappedContinuation = continuation else {
            preconditionFailure("Failed to initialize route change stream continuation")
        }
        self.routeChangeContinuation = unwrappedContinuation
    }
    
    deinit {
        routeChangeContinuation.finish()
    }
    
    // MARK: - Current Audio Output (Computed)
    
    /// Current active audio output device
    ///
    /// This is a computed property that always queries the actual system state
    /// from `AVAudioSession.currentRoute`, ensuring it never drifts from reality.
    public var currentAudioOutput: AudioOutputDeviceType {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        
        guard let output = route.outputs.first else {
            return .builtInSpeaker
        }
        
        return AudioOutputDeviceType.from(portType: output.portType, portName: output.portName)
        #else
        return .systemDefault
        #endif
    }
    
    // MARK: - Available Devices
    
    /// List of available audio output devices
    ///
    /// Returns all currently available output devices including built-in speaker,
    /// receiver, and any connected Bluetooth or wired devices.
    public var availableAudioOutputDevices: [AudioOutputDeviceType] {
        #if os(iOS)
        var devices: [AudioOutputDeviceType] = []
        let session = AVAudioSession.sharedInstance()
        
        // Built-in devices are always available
        devices.append(.builtInSpeaker)
        devices.append(.builtInReceiver)
        
        // Check for connected Bluetooth devices
        let availableInputs = session.availableInputs ?? []
        let currentRoute = session.currentRoute
        
        // Get all unique Bluetooth devices from available inputs and current route
        var bluetoothDevices: Set<String> = []
        
        // Check available inputs for Bluetooth devices
        for input in availableInputs {
            if input.portType == .bluetoothHFP || input.portType == .bluetoothA2DP || input.portType == .bluetoothLE {
                let name = input.portName
                if !name.isEmpty {
                    bluetoothDevices.insert(name)
                }
            }
        }
        
        // Check current route outputs for Bluetooth devices
        for output in currentRoute.outputs {
            if output.portType == .bluetoothHFP || output.portType == .bluetoothA2DP || output.portType == .bluetoothLE {
                let name = output.portName
                if !name.isEmpty {
                    bluetoothDevices.insert(name)
                }
            }
        }
        
        // Add Bluetooth devices to list
        for name in bluetoothDevices {
            devices.append(.bluetooth(name: name))
        }
        
        // Check for wired headphones
        for output in currentRoute.outputs {
            if output.portType == .headphones {
                let name = output.portName
                devices.append(.wiredHeadphones(name: name.isEmpty ? nil : name))
                break
            }
        }
        
        return devices
        #else
        return [.builtInSpeaker, .builtInReceiver]
        #endif
    }
    
    // MARK: - Configuration
    
    /// Configures the audio session for voice chat
    ///
    /// Sets up the AVAudioSession with appropriate category, mode, and options
    /// for real-time voice communication.
    ///
    /// - Parameter defaultToSpeaker: If true, routes audio to speaker by default.
    ///   If false, uses the system default (typically earpiece for voice chat mode).
    /// - Throws: Error if audio session configuration fails
    public func configureForVoiceChat(defaultToSpeaker: Bool) async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        
        // Build options based on configuration
        var options: AVAudioSession.CategoryOptions = [
            .allowBluetooth,
            .allowBluetoothA2DP,
            .mixWithOthers
        ]
        
        if defaultToSpeaker {
            options.insert(.defaultToSpeaker)
        }
        
        do {
            // Configure for voice chat with echo cancellation
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: options
            )
            
            // Set preferred sample rate for WebRTC/Realtime (24kHz for OpenAI)
            try session.setPreferredSampleRate(24000)
            
            // Activate the session
            try session.setActive(true)
            
            // If defaultToSpeaker, explicitly override to ensure speaker routing
            // .voiceChat mode defaults to receiver, so we need explicit override
            if defaultToSpeaker {
                try session.overrideOutputAudioPort(.speaker)
            }
            
            isConfigured = true
            print("[AudioSessionManager] ✅ Audio session configured (defaultToSpeaker: \(defaultToSpeaker))")
            
        } catch {
            print("[AudioSessionManager] ❌ Failed to configure audio session: \(error)")
            throw error
        }
        #else
        // macOS doesn't require explicit audio session configuration
        isConfigured = true
        #endif
    }
    
    /// Deactivates the audio session
    public func deactivate() async {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isConfigured = false
            print("[AudioSessionManager] ✅ Audio session deactivated")
        } catch {
            print("[AudioSessionManager] ⚠️ Failed to deactivate audio session: \(error)")
        }
        #else
        isConfigured = false
        #endif
    }
    
    // MARK: - Set Audio Output
    
    /// Sets the audio output device with verification
    ///
    /// This method changes the audio output and verifies the route actually changed.
    /// If the initial attempt fails for speaker output, it will retry the override.
    ///
    /// - Parameter device: The target audio output device
    /// - Throws: Error if the device change fails
    public func setAudioOutput(device: AudioOutputDeviceType) async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        
        // Build options based on device
        var options: AVAudioSession.CategoryOptions = [
            .allowBluetooth,
            .allowBluetoothA2DP,
            .mixWithOthers
        ]
        var portOverride: AVAudioSession.PortOverride = .none
        
        switch device {
        case .builtInSpeaker:
            // Force speaker output
            options.insert(.defaultToSpeaker)
            portOverride = .speaker
            
        case .builtInReceiver:
            // Force earpiece (remove speaker override)
            // No defaultToSpeaker - voiceChat mode routes to receiver
            portOverride = .none
            
        case .bluetooth, .wiredHeadphones:
            // External devices - no defaultToSpeaker, let system route
            portOverride = .none
            
        case .systemDefault:
            // Let system choose
            portOverride = .none
            
        case .smart:
            // Smart mode: Use Bluetooth if available, otherwise speaker
            let bluetoothConnected = availableAudioOutputDevices.contains { $0.isBluetooth }
            if bluetoothConnected {
                portOverride = .none
            } else {
                options.insert(.defaultToSpeaker)
                portOverride = .speaker
            }
        }
        
        do {
            // Step 1: Clear any existing override
            try session.overrideOutputAudioPort(.none)
            
            // Step 2: Reconfigure the category with the new options
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: options
            )
            
            // Step 3: Ensure session is active
            if !session.isOtherAudioPlaying {
                try session.setActive(true)
            }
            
            // Step 4: Apply port override
            try session.overrideOutputAudioPort(portOverride)
            
            // Step 5: Wait for route change to take effect
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            // Step 6: Verify route actually changed (especially for speaker)
            let verifyRoute = session.currentRoute
            let actualOutput = verifyRoute.outputs.first?.portType ?? .builtInReceiver
            
            if device == .builtInSpeaker && actualOutput != .builtInSpeaker {
                // Try override again
                try session.overrideOutputAudioPort(.speaker)
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
            
            let finalDevice = currentAudioOutput
            print("[AudioSessionManager] 🔊 Audio output set to: \(finalDevice)")
            
            // Emit route change event
            routeChangeContinuation.yield(finalDevice)
            
        } catch {
            print("[AudioSessionManager] ❌ Failed to set audio output: \(error)")
            throw error
        }
        #endif
    }
    
    // MARK: - Route Change Observation
    
    /// Starts observing audio route changes
    ///
    /// When route changes occur (e.g., Bluetooth connects/disconnects),
    /// the new device will be emitted via `routeChangeStream`.
    public func startRouteChangeObservation() {
        guard !isObserving else { return }
        
        #if os(iOS)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            // Extract reason from notification
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) ?? .unknown
            
            print("[AudioSessionManager] 🔄 Route change detected: \(reason)")
            
            // Dispatch to actor context
            Task {
                await self.handleRouteChange(reason: reason)
            }
        }
        
        isObserving = true
        print("[AudioSessionManager] 👂 Started route change observation")
        #endif
    }
    
    /// Stops observing audio route changes
    public func stopRouteChangeObservation() {
        guard isObserving else { return }
        
        #if os(iOS)
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        #endif
        
        isObserving = false
        print("[AudioSessionManager] 🔇 Stopped route change observation")
    }
    
    /// Handles a route change notification
    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        let newDevice = currentAudioOutput
        
        print("[AudioSessionManager] 📍 New route: \(newDevice) (reason: \(reason.rawValue))")
        
        // Emit the new device to stream
        routeChangeContinuation.yield(newDevice)
    }
}

