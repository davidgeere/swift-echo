// AudioOutputDeviceType.swift
// Echo - Audio
// Audio output device type enumeration

import AVFoundation
import Foundation

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

    /// Smart default: Bluetooth if connected, otherwise speaker with echo protection
    /// Best for voice conversations - provides speaker output by default while
    /// automatically switching to Bluetooth when available
    case smart
    
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
        case .smart:
            return "Smart (Bluetooth/Speaker)"
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

    /// Whether this device type may produce echo (speaker output picked up by microphone)
    public var mayProduceEcho: Bool {
        switch self {
        case .builtInSpeaker:
            return true
        case .bluetooth:
            // Bluetooth speakers may produce echo, earbuds usually don't
            // We conservatively assume they may
            return true
        case .builtInReceiver, .wiredHeadphones:
            return false
        case .systemDefault, .smart:
            // Unknown, assume may produce echo
            return true
        }
    }
    
    /// Creates an AudioOutputDeviceType from AVAudioSession port type and name
    /// - Parameters:
    ///   - portType: The AVAudioSession port type
    ///   - portName: Optional port name
    /// - Returns: AudioOutputDeviceType corresponding to the port
    #if os(iOS)
    static func from(portType: AVAudioSession.Port, portName: String) -> AudioOutputDeviceType {
        let name: String? = portName.isEmpty ? nil : portName
        
        switch portType {
        case .builtInSpeaker:
            return .builtInSpeaker
        case .builtInReceiver:
            return .builtInReceiver
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
            return .bluetooth(name: name)
        case .headphones:
            return .wiredHeadphones(name: name)
        default:
            return .systemDefault
        }
    }
    #endif
}
