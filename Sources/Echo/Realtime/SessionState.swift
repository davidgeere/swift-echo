// SessionState.swift
// Echo - Realtime API
// Represents the state of a Realtime session

import Foundation

/// Represents the state of a Realtime session
public enum SessionState: String, Sendable {
    /// Session is not connected
    case disconnected

    /// Session is connecting
    case connecting

    /// Session is connected and active
    case connected

    /// Session is reconnecting after disconnection
    case reconnecting

    /// Session has failed
    case failed
}
