// WebRTCTransportTests.swift
// Echo Tests
// Tests for WebRTC transport layer components

import Testing
@testable import Echo
import Foundation

@Suite("WebRTC Transport Tests")
struct WebRTCTransportTests {
    
    // MARK: - Transport Type Tests
    
    @Test("RealtimeTransportType enum values")
    func transportTypeEnumValues() {
        #expect(RealtimeTransportType.webSocket.rawValue == "webSocket")
        #expect(RealtimeTransportType.webRTC.rawValue == "webRTC")
        #expect(RealtimeTransportType.allCases.count == 2)
    }
    
    @Test("RealtimeTransportType is Sendable")
    func transportTypeIsSendable() async {
        let type: RealtimeTransportType = .webRTC
        
        await Task {
            #expect(type == .webRTC)
        }.value
    }
    
    // MARK: - Transport Error Tests
    
    @Test("RealtimeTransportError descriptions")
    func transportErrorDescriptions() {
        let errors: [RealtimeTransportError] = [
            .alreadyConnected,
            .notConnected,
            .connectionFailed(NSError(domain: "test", code: 1)),
            .ephemeralKeyFailed(NSError(domain: "test", code: 2)),
            .sdpExchangeFailed(NSError(domain: "test", code: 3)),
            .dataChannelFailed("test message"),
            .sendFailed(NSError(domain: "test", code: 4)),
            .audioSetupFailed(NSError(domain: "test", code: 5)),
            .unsupportedOperation("test operation")
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
    
    @Test("Transport errors are Sendable")
    func transportErrorsAreSendable() async {
        let error = RealtimeTransportError.notConnected
        
        await Task {
            #expect(error.errorDescription == "Transport is not connected")
        }.value
    }
    
    // MARK: - WebSocket Transport Tests
    
    @Test("WebSocketTransport initializes correctly")
    func webSocketTransportInitializes() async {
        let transport = WebSocketTransport()
        
        let isConnected = await transport.isConnected
        let handlesAudio = await transport.handlesAudioNatively
        
        #expect(!isConnected)
        #expect(!handlesAudio) // WebSocket does NOT handle audio natively
    }
    
    @Test("WebSocketTransport throws when sending while disconnected")
    func webSocketTransportThrowsWhenDisconnected() async {
        let transport = WebSocketTransport()
        
        do {
            try await transport.send(eventJSON: "{}")
            #expect(Bool(false), "Should have thrown")
        } catch let error as RealtimeTransportError {
            if case .notConnected = error {
                #expect(true)
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }
    
    @Test("WebSocketTransport sendAudio sends input_audio_buffer.append event")
    func webSocketTransportSendAudio() async {
        let transport = WebSocketTransport()
        
        // Can't test actual sending without connection, but we verify it throws notConnected
        do {
            try await transport.sendAudio("base64audio")
            #expect(Bool(false), "Should have thrown")
        } catch let error as RealtimeTransportError {
            if case .notConnected = error {
                #expect(true)
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }
    
    // MARK: - WebRTC Transport Tests
    
    @Test("WebRTCTransport initializes correctly")
    func webRTCTransportInitializes() async {
        let transport = WebRTCTransport()
        
        let isConnected = await transport.isConnected
        let handlesAudio = await transport.handlesAudioNatively
        
        #expect(!isConnected)
        #expect(handlesAudio) // WebRTC DOES handle audio natively
    }
    
    @Test("WebRTCTransport sendAudio throws unsupportedOperation")
    func webRTCTransportSendAudioThrows() async {
        let transport = WebRTCTransport()
        
        do {
            try await transport.sendAudio("base64audio")
            #expect(Bool(false), "Should have thrown")
        } catch let error as RealtimeTransportError {
            if case .unsupportedOperation = error {
                #expect(true)
            } else {
                #expect(Bool(false), "Wrong error type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }
    
    @Test("WebRTCTransport throws when sending while disconnected")
    func webRTCTransportThrowsWhenDisconnected() async {
        let transport = WebRTCTransport()
        
        do {
            try await transport.send(eventJSON: "{}")
            #expect(Bool(false), "Should have thrown")
        } catch let error as RealtimeTransportError {
            if case .notConnected = error {
                #expect(true)
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }
    
    // MARK: - Configuration Tests
    
    @Test("EchoConfiguration transportType defaults to webSocket")
    func echoConfigurationDefaultTransport() {
        let config = EchoConfiguration()
        #expect(config.transportType == .webSocket)
    }
    
    @Test("EchoConfiguration accepts webRTC transport")
    func echoConfigurationWebRTCTransport() {
        let config = EchoConfiguration(transportType: .webRTC)
        #expect(config.transportType == .webRTC)
    }
    
    @Test("RealtimeClientConfiguration transportType defaults to webSocket")
    func realtimeClientConfigurationDefaultTransport() {
        let config = RealtimeClientConfiguration.default
        #expect(config.transportType == .webSocket)
    }
    
    @Test("RealtimeClientConfiguration accepts webRTC transport")
    func realtimeClientConfigurationWebRTCTransport() {
        let config = RealtimeClientConfiguration(
            model: .gptRealtime,
            transportType: .webRTC
        )
        #expect(config.transportType == .webRTC)
    }
    
    @Test("EchoConfiguration toRealtimeClientConfiguration preserves transportType")
    func echoConfigurationConversion() {
        let echoConfig = EchoConfiguration(transportType: .webRTC)
        let realtimeConfig = echoConfig.toRealtimeClientConfiguration()
        #expect(realtimeConfig.transportType == .webRTC)
    }
}

@Suite("WebRTC Session Manager Tests")
struct WebRTCSessionManagerTests {
    
    @Test("SessionConfiguration initializes with model")
    func sessionConfigurationInit() {
        let config = WebRTCSessionManager.SessionConfiguration(model: "gpt-realtime")
        
        #expect(config.type == "realtime")
        #expect(config.model == "gpt-realtime")
        #expect(config.voice == nil)
        #expect(config.instructions == nil)
    }
    
    @Test("SessionConfiguration initializes with all parameters")
    func sessionConfigurationFullInit() {
        let config = WebRTCSessionManager.SessionConfiguration(
            model: "gpt-realtime",
            voice: "alloy",
            instructions: "Test instructions",
            turnDetection: ["type": "server_vad"],
            tools: [["name": "test_tool"]]
        )
        
        #expect(config.type == "realtime")
        #expect(config.model == "gpt-realtime")
        #expect(config.voice == "alloy")
        #expect(config.instructions == "Test instructions")
        #expect(config.turnDetectionJSON != nil)
        #expect(config.toolsJSON != nil)
    }
    
    @Test("SessionConfiguration is Sendable")
    func sessionConfigurationIsSendable() async {
        let config = WebRTCSessionManager.SessionConfiguration(model: "gpt-realtime")
        
        await Task {
            #expect(config.model == "gpt-realtime")
        }.value
    }
    
    @Test("SessionConfiguration toJSON generates valid structure")
    func sessionConfigurationToJSON() {
        let config = WebRTCSessionManager.SessionConfiguration(
            model: "gpt-realtime",
            voice: "shimmer"
        )
        
        let json = config.toJSON()
        
        guard let session = json["session"] as? [String: Any] else {
            #expect(Bool(false), "Missing session key")
            return
        }
        
        #expect(session["type"] as? String == "realtime")
        #expect(session["model"] as? String == "gpt-realtime")
        
        guard let audio = session["audio"] as? [String: Any] else {
            #expect(Bool(false), "Missing audio key")
            return
        }
        
        guard let output = audio["output"] as? [String: Any] else {
            #expect(Bool(false), "Missing output key")
            return
        }
        
        #expect(output["voice"] as? String == "shimmer")
    }
    
    @Test("WebRTCSessionManager initializes")
    func sessionManagerInit() async {
        let manager = WebRTCSessionManager()
        
        let hasValidKey = await manager.hasValidEphemeralKey
        #expect(!hasValidKey)
    }
    
    @Test("WebRTCSessionManager clearEphemeralKey resets state")
    func sessionManagerClear() async {
        let manager = WebRTCSessionManager()
        
        await manager.clearEphemeralKey()
        
        let hasValidKey = await manager.hasValidEphemeralKey
        #expect(!hasValidKey)
    }
}

@Suite("WebRTC Audio Handler Tests")
struct WebRTCAudioHandlerTests {
    
    @Test("WebRTCAudioHandler initializes in idle state")
    func audioHandlerInit() async {
        let handler = WebRTCAudioHandler()
        
        let isReady = await handler.isReady
        #expect(!isReady)
    }
    
    @Test("WebRTCAudioHandler mute state")
    func audioHandlerMute() async {
        let handler = WebRTCAudioHandler()
        
        let initialMuted = await handler.isAudioMuted
        #expect(!initialMuted)
        
        await handler.setMuted(true)
        
        let nowMuted = await handler.isAudioMuted
        #expect(nowMuted)
        
        await handler.setMuted(false)
        
        let finalMuted = await handler.isAudioMuted
        #expect(!finalMuted)
    }
    
    @Test("WebRTCAudioHandler currentAudioOutput defaults to systemDefault")
    func audioHandlerDefaultOutput() async {
        let handler = WebRTCAudioHandler()
        
        let output = await handler.currentAudioOutput
        #expect(output == .systemDefault)
    }
}

