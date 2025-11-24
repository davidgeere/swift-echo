// AudioOutputDeviceType.swift
// Echo - Audio
// Audio output device type enumeration

import Foundation
import AVFoundation

/// Represents the type of audio output device
public enum AudioOutputDeviceType: Sendable, Equatable {
    /// Built-in speaker
    case builtInSpeaker
    
    /// Built-in receiver (earpiece)
    case builtInReceiver
    
    /// Bluetooth audio device
    /// - Parameter name: Optional device name (e.g., "AirPods Pro", "External Speaker")
    case bluetooth(name: String?)
    
    /// Wired headphones
    /// - Parameter name: Optional device name
    case wiredHeadphones(name: String?)
    
    /// Let system choose the default route
    case systemDefault
    
    /// Human-readable description for UI display
    public var description: String {
        switch self {
        case .builtInSpeaker:
            return "Speaker"
        case .builtInReceiver:
            return "Earpiece"
        case .bluetooth(let name):
            return name ?? "Bluetooth"
        case .wiredHeadphones(let name):
            return name ?? "Headphones"
        case .systemDefault:
            return "System Default"
        }
    }
    
    /// Whether this is a Bluetooth device
    public var isBluetooth: Bool {
        switch self {
        case .bluetooth:
            return true
        default:
            return false
        }
    }
    
    /// Creates an AudioOutputDeviceType from AVAudioSession port type and name
    /// - Parameters:
    ///   - portType: The AVAudioSession port type
    ///   - portName: Optional port name
    /// - Returns: AudioOutputDeviceType corresponding to the port
    #if os(iOS)
    static func from(portType: AVAudioSession.Port, portName: String?) -> AudioOutputDeviceType {
        switch portType {
        case .builtInSpeaker:
            return .builtInSpeaker
        case .builtInReceiver:
            return .builtInReceiver
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
            return .bluetooth(name: portName)
        case .headphones:
            return .wiredHeadphones(name: portName)
        default:
            return .systemDefault
        }
    }
    #endif
}

