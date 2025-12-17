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
        public let modalities: [String]  // Output modalities: ["audio"] or ["text"]
        public let voice: String?
        public let speed: Double?
        public let instructions: String?
        public let turnDetectionJSON: String?
        public let toolsJSON: String?
        public let transcriptionJSON: String?  // SOLVE-4: Add transcription config
        public let inputAudioJSON: String?  // Input audio configuration (noise reduction)
        public let idleTimeoutMs: Int?  // Idle timeout in milliseconds
        
        public init(
            model: String,
            modalities: [String] = ["audio"],  // Default to audio for backwards compatibility
            voice: String? = nil,
            speed: Double? = nil,
            instructions: String? = nil,
            turnDetection: [String: Any]? = nil,
            tools: [[String: Any]]? = nil,
            transcription: [String: Any]? = nil,  // SOLVE-4: Add transcription parameter
            inputAudio: [String: Any]? = nil,  // Input audio configuration
            idleTimeoutMs: Int? = nil  // Idle timeout
        ) {
            self.type = "realtime"
            self.model = model
            self.modalities = modalities
            self.voice = voice
            self.speed = speed
            self.instructions = instructions
            
            // Convert to JSON strings for Sendable compliance
            // Round threshold to avoid floating-point precision issues
            if var turnDetection = turnDetection {
                // #region agent log H1-H4
                print("[DEBUG-H4] 🔍 turnDetection received: \(turnDetection)")
                // #endregion
                
                // Convert threshold to Decimal to avoid IEEE 754 floating-point precision issues
                // Double(0.7) is stored as 0.69999999999999996 in binary
                // Decimal can exactly represent base-10 decimals
                if let threshold = turnDetection["threshold"] as? Double {
                    // Format to 2 decimal places and convert to Decimal
                    let formattedString = String(format: "%.2f", threshold)
                    let decimalThreshold = Decimal(string: formattedString) ?? Decimal(threshold)
                    turnDetection["threshold"] = decimalThreshold
                    
                    // #region agent log H4
                    print("[DEBUG-H4] 🔍 threshold: original=\(threshold) decimal=\(decimalThreshold)")
                    // #endregion
                }
                if let data = try? JSONSerialization.data(withJSONObject: turnDetection) {
                    self.turnDetectionJSON = String(data: data, encoding: .utf8)
                    
                    // #region agent log H2
                    print("[DEBUG-H2] 🔍 turnDetectionJSON after serialization: \(self.turnDetectionJSON ?? "nil")")
                    // #endregion
                } else {
                    self.turnDetectionJSON = nil
                }
            } else {
                self.turnDetectionJSON = nil
                
                // #region agent log H3
                print("[DEBUG-H3] 🔍 No turnDetection provided to SessionConfiguration")
                // #endregion
            }
            
            if let tools = tools,
               let data = try? JSONSerialization.data(withJSONObject: tools) {
                self.toolsJSON = String(data: data, encoding: .utf8)
            } else {
                self.toolsJSON = nil
            }
            
            // SOLVE-4: Convert transcription config to JSON string
            if let transcription = transcription,
               let data = try? JSONSerialization.data(withJSONObject: transcription) {
                self.transcriptionJSON = String(data: data, encoding: .utf8)
                print("[DEBUG-SOLVE-4] 🎤 transcriptionJSON: \(self.transcriptionJSON ?? "nil")")
            } else {
                self.transcriptionJSON = nil
            }
            
            // Convert input audio config to JSON string
            if let inputAudio = inputAudio,
               let data = try? JSONSerialization.data(withJSONObject: inputAudio) {
                self.inputAudioJSON = String(data: data, encoding: .utf8)
            } else {
                self.inputAudioJSON = nil
            }
            
            // Store idle timeout
            self.idleTimeoutMs = idleTimeoutMs
        }
        
        func toJSON() -> [String: Any] {
            var session: [String: Any] = [
                "type": type,
                "model": model,
                "output_modalities": modalities
            ]
            
            print("[DEBUG-MODALITIES] 🎯 Session output_modalities: \(modalities)")
            
            // Audio configuration (GA API format)
            var audio: [String: Any] = [:]
            
            // Input audio format
            var input: [String: Any] = [
                "format": [
                    "type": "audio/pcm",
                    "rate": 24000
                ]
            ]
            
            // SOLVE-4: Add transcription config to input
            if let transcriptionJSON = transcriptionJSON,
               let transcriptionData = transcriptionJSON.data(using: .utf8),
               let transcription = try? JSONSerialization.jsonObject(with: transcriptionData) as? [String: Any] {
                input["transcription"] = transcription
                print("[DEBUG-SOLVE-4] 🎤 Added transcription to input: \(transcription)")
            }
            
            audio["input"] = input
            
            // Output audio format - SOLVE-2: Add rate to output format
            print("[DEBUG-SOLVE-2] 🔧 Adding rate to output format")
            var output: [String: Any] = [
                "format": [
                    "type": "audio/pcm",
                    "rate": 24000
                ]
            ]
            if let voice = voice {
                output["voice"] = voice
            }
            if let speed = speed {
                // Format speed to 2 decimal places to preserve values like 0.25
                let formattedString = String(format: "%.2f", speed)
                if let decimalSpeed = Decimal(string: formattedString) {
                    output["speed"] = NSDecimalNumber(decimal: decimalSpeed)
                }
                print("[DEBUG] 🔧 Adding speed to output: \(formattedString)")
            }
            audio["output"] = output
            
            session["audio"] = audio
            
            if let instructions = instructions {
                session["instructions"] = instructions
            }
            
            // NOTE: Model audio transcripts come automatically via response.output_audio_transcript.delta events
            // No special session configuration needed - just listen for the correct event name
            
            // #region agent log SOLVE-1
            print("[DEBUG-SOLVE-1] 🔧 toJSON() called - applying threshold fix")
            // #endregion
            
            if let turnDetectionJSON = turnDetectionJSON,
               let turnDetectionData = turnDetectionJSON.data(using: .utf8),
               var turnDetection = try? JSONSerialization.jsonObject(with: turnDetectionData) as? [String: Any] {
                
                // H6 FIX: JSONSerialization.jsonObject converts 0.7 back to Double!
                // Re-apply Decimal conversion here too
                if let threshold = turnDetection["threshold"] as? Double {
                    let formattedString = String(format: "%.2f", threshold)
                    let decimalThreshold = Decimal(string: formattedString) ?? Decimal(threshold)
                    turnDetection["threshold"] = decimalThreshold
                    print("[DEBUG-SOLVE-1] 🔧 Fixed threshold in toJSON: \(threshold) → \(decimalThreshold)")
                }
                
                // Add idle timeout to turn_detection if specified (nullable field)
                if let idleTimeoutMs = idleTimeoutMs {
                    turnDetection["idle_timeout_ms"] = idleTimeoutMs
                    print("[DEBUG] 🔧 Adding idle_timeout_ms to turn_detection: \(idleTimeoutMs)")
                }
                
                if var inputAudio = session["audio"] as? [String: Any],
                   var inputConfig = inputAudio["input"] as? [String: Any] {
                    inputConfig["turn_detection"] = turnDetection
                    inputAudio["input"] = inputConfig
                    session["audio"] = inputAudio
                }
            }
            
            if let toolsJSON = toolsJSON,
               let toolsData = toolsJSON.data(using: .utf8),
               let tools = try? JSONSerialization.jsonObject(with: toolsData) as? [[String: Any]],
               !tools.isEmpty {
                session["tools"] = tools
            }
            
            // Add input audio configuration (noise reduction) to input
            if let inputAudioJSON = inputAudioJSON,
               let inputAudioData = inputAudioJSON.data(using: .utf8),
               let inputAudioConfig = try? JSONSerialization.jsonObject(with: inputAudioData) as? [String: Any] {
                if var audioConfig = session["audio"] as? [String: Any],
                   var inputConfig = audioConfig["input"] as? [String: Any] {
                    // Merge noise reduction into input config
                    for (key, value) in inputAudioConfig {
                        inputConfig[key] = value
                    }
                    audioConfig["input"] = inputConfig
                    session["audio"] = audioConfig
                }
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
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        
        // #region agent log H2-H5
        let bodyString = String(data: bodyData, encoding: .utf8) ?? "nil"
        print("[DEBUG-H2-H5] 🔍 FULL REQUEST BODY: \(bodyString)")
        // #endregion
        
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

