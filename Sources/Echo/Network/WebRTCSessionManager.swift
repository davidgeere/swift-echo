// WebRTCSessionManager.swift
// Echo - Network Layer
// Manages WebRTC session establishment with OpenAI Realtime API

import Foundation

/// Manages WebRTC session establishment with the OpenAI Realtime API
///
/// This actor handles:
/// 1. Fetching ephemeral keys from `/v1/realtime/client_secrets`
/// 2. Exchanging SDP with OpenAI via `/v1/realtime/calls`
///
/// The developer never sees these operations - they just provide their API key
/// and the session manager handles all the WebRTC handshake complexity.
public actor WebRTCSessionManager {
    // MARK: - Types
    
    /// Response from the client_secrets endpoint
    public struct ClientSecretResponse: Codable, Sendable {
        public let value: String
        public let expiresAt: Int?
        
        enum CodingKeys: String, CodingKey {
            case value
            case expiresAt = "expires_at"
        }
    }
    
    /// Session configuration for WebRTC
    public struct SessionConfiguration: Sendable {
        public let type: String
        public let model: String
        public let voice: String?
        public let instructions: String?
        public let turnDetectionJSON: String?
        public let toolsJSON: String?
        
        public init(
            model: String,
            voice: String? = nil,
            instructions: String? = nil,
            turnDetection: [String: Any]? = nil,
            tools: [[String: Any]]? = nil
        ) {
            self.type = "realtime"
            self.model = model
            self.voice = voice
            self.instructions = instructions
            
            // Convert to JSON strings for Sendable compliance
            if let turnDetection = turnDetection,
               let data = try? JSONSerialization.data(withJSONObject: turnDetection) {
                self.turnDetectionJSON = String(data: data, encoding: .utf8)
            } else {
                self.turnDetectionJSON = nil
            }
            
            if let tools = tools,
               let data = try? JSONSerialization.data(withJSONObject: tools) {
                self.toolsJSON = String(data: data, encoding: .utf8)
            } else {
                self.toolsJSON = nil
            }
        }
        
        func toJSON() -> [String: Any] {
            var session: [String: Any] = [
                "type": type,
                "model": model
            ]
            
            // Audio configuration (GA API format)
            var audio: [String: Any] = [:]
            
            // Input audio format
            audio["input"] = [
                "format": [
                    "type": "audio/pcm",
                    "rate": 24000
                ]
            ]
            
            // Output audio format
            var output: [String: Any] = [
                "format": [
                    "type": "audio/pcm"
                ]
            ]
            if let voice = voice {
                output["voice"] = voice
            }
            audio["output"] = output
            
            session["audio"] = audio
            
            if let instructions = instructions {
                session["instructions"] = instructions
            }
            
            if let turnDetectionJSON = turnDetectionJSON,
               let turnDetectionData = turnDetectionJSON.data(using: .utf8),
               let turnDetection = try? JSONSerialization.jsonObject(with: turnDetectionData) as? [String: Any] {
                if var inputAudio = session["audio"] as? [String: Any],
                   var input = inputAudio["input"] as? [String: Any] {
                    input["turn_detection"] = turnDetection
                    inputAudio["input"] = input
                    session["audio"] = inputAudio
                }
            }
            
            if let toolsJSON = toolsJSON,
               let toolsData = toolsJSON.data(using: .utf8),
               let tools = try? JSONSerialization.jsonObject(with: toolsData) as? [[String: Any]],
               !tools.isEmpty {
                session["tools"] = tools
            }
            
            return ["session": session]
        }
    }
    
    // MARK: - Properties
    
    private let baseURL = "https://api.openai.com/v1"
    private var currentEphemeralKey: String?
    private var ephemeralKeyExpiry: Date?
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public Methods
    
    /// Fetches an ephemeral key for WebRTC connection
    ///
    /// Uses the provided API key to request an ephemeral key from OpenAI.
    /// The ephemeral key is safe to use in client environments and expires after
    /// a short period.
    ///
    /// - Parameters:
    ///   - apiKey: The OpenAI API key
    ///   - configuration: Session configuration including model and voice
    /// - Returns: The ephemeral key value
    /// - Throws: RealtimeTransportError if the request fails
    public func fetchEphemeralKey(
        apiKey: String,
        configuration: SessionConfiguration
    ) async throws -> String {
        print("[WebRTCSessionManager] 🔑 Fetching ephemeral key...")
        
        let url = URL(string: "\(baseURL)/realtime/client_secrets")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body
        let body = configuration.toJSON()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RealtimeTransportError.ephemeralKeyFailed(
                    NSError(domain: "WebRTCSessionManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Invalid response type"
                    ])
                )
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw RealtimeTransportError.ephemeralKeyFailed(
                    NSError(domain: "WebRTCSessionManager", code: httpResponse.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorBody)"
                    ])
                )
            }
            
            let decoder = JSONDecoder()
            let secretResponse = try decoder.decode(ClientSecretResponse.self, from: data)
            
            // Store the ephemeral key
            currentEphemeralKey = secretResponse.value
            if let expiresAt = secretResponse.expiresAt {
                ephemeralKeyExpiry = Date(timeIntervalSince1970: TimeInterval(expiresAt))
            }
            
            print("[WebRTCSessionManager] ✅ Ephemeral key obtained successfully")
            return secretResponse.value
            
        } catch let error as RealtimeTransportError {
            throw error
        } catch {
            throw RealtimeTransportError.ephemeralKeyFailed(error)
        }
    }
    
    /// Exchanges SDP with OpenAI to establish WebRTC connection
    ///
    /// Posts the local SDP offer to OpenAI and receives the remote SDP answer.
    /// This is step 2 of the WebRTC handshake after fetching the ephemeral key.
    ///
    /// - Parameters:
    ///   - sdpOffer: The local SDP offer string
    ///   - ephemeralKey: The ephemeral key from fetchEphemeralKey
    /// - Returns: The remote SDP answer string
    /// - Throws: RealtimeTransportError if the exchange fails
    public func exchangeSDP(
        sdpOffer: String,
        ephemeralKey: String
    ) async throws -> String {
        print("[WebRTCSessionManager] 📡 Exchanging SDP...")
        
        let url = URL(string: "\(baseURL)/realtime/calls")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(ephemeralKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = sdpOffer.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RealtimeTransportError.sdpExchangeFailed(
                    NSError(domain: "WebRTCSessionManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Invalid response type"
                    ])
                )
            }
            
            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw RealtimeTransportError.sdpExchangeFailed(
                    NSError(domain: "WebRTCSessionManager", code: httpResponse.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorBody)"
                    ])
                )
            }
            
            guard let sdpAnswer = String(data: data, encoding: .utf8) else {
                throw RealtimeTransportError.sdpExchangeFailed(
                    NSError(domain: "WebRTCSessionManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to decode SDP answer"
                    ])
                )
            }
            
            print("[WebRTCSessionManager] ✅ SDP exchange successful")
            return sdpAnswer
            
        } catch let error as RealtimeTransportError {
            throw error
        } catch {
            throw RealtimeTransportError.sdpExchangeFailed(error)
        }
    }
    
    /// Checks if the current ephemeral key is still valid
    public var hasValidEphemeralKey: Bool {
        guard let key = currentEphemeralKey, let expiry = ephemeralKeyExpiry else {
            return false
        }
        // Add a 30-second buffer before expiry
        return Date().addingTimeInterval(30) < expiry && !key.isEmpty
    }
    
    /// Clears the stored ephemeral key
    public func clearEphemeralKey() {
        currentEphemeralKey = nil
        ephemeralKeyExpiry = nil
    }
}

