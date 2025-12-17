// OutputModalityTests.swift
// Echo Tests - Realtime API
// Tests for OutputModality enum and modality switching

import Testing
@testable import Echo

/// Tests for OutputModality enum functionality
@Suite
struct OutputModalityTests {
    
    // MARK: - API Value Tests
    
    @Test
    func audioModalityReturnsCorrectApiValue() {
        let modality = OutputModality.audio
        #expect(modality.apiValue == ["audio"])
    }
    
    @Test
    func textModalityReturnsCorrectApiValue() {
        let modality = OutputModality.text
        #expect(modality.apiValue == ["text"])
    }
    
    // MARK: - Properties Tests
    
    @Test
    func audioModalityProducesAudio() {
        let modality = OutputModality.audio
        #expect(modality.producesAudio == true)
    }
    
    @Test
    func textModalityDoesNotProduceAudio() {
        let modality = OutputModality.text
        #expect(modality.producesAudio == false)
    }
    
    @Test
    func bothModalitiesProduceText() {
        // Audio mode produces transcript, text mode produces text
        #expect(OutputModality.audio.producesText == true)
        #expect(OutputModality.text.producesText == true)
    }
    
    // MARK: - Description Tests
    
    @Test
    func audioModalityHasCorrectDescription() {
        let modality = OutputModality.audio
        #expect(modality.description == "Audio (voice + transcript)")
    }
    
    @Test
    func textModalityHasCorrectDescription() {
        let modality = OutputModality.text
        #expect(modality.description == "Text only")
    }
    
    // MARK: - CaseIterable Tests
    
    @Test
    func allCasesAreAvailable() {
        let cases = OutputModality.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.audio))
        #expect(cases.contains(.text))
    }
    
    // MARK: - Codable Tests
    
    @Test
    func modalityIsEncodableAndDecodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        // Test audio modality
        let audioData = try encoder.encode(OutputModality.audio)
        let decodedAudio = try decoder.decode(OutputModality.self, from: audioData)
        #expect(decodedAudio == .audio)
        
        // Test text modality
        let textData = try encoder.encode(OutputModality.text)
        let decodedText = try decoder.decode(OutputModality.self, from: textData)
        #expect(decodedText == .text)
    }
}

/// Tests for RealtimeSession with OutputModality
@Suite
struct RealtimeSessionModalityTests {
    
    @Test
    func defaultOutputModalityIsAudio() {
        let session = RealtimeSession(model: .gptRealtime)
        #expect(session.outputModality == .audio)
    }
    
    @Test
    func outputModalityCanBeSetToText() {
        let session = RealtimeSession(
            model: .gptRealtime,
            outputModality: .text
        )
        #expect(session.outputModality == .text)
    }
    
    @Test
    func toRealtimeFormatUsesCorrectModalitiesForAudio() {
        let session = RealtimeSession(
            model: .gptRealtime,
            outputModality: .audio
        )
        
        let format = session.toRealtimeFormat()
        
        guard let modalities = format["modalities"] as? [String] else {
            Issue.record("modalities should be an array of strings")
            return
        }
        
        #expect(modalities == ["audio"])
    }
    
    @Test
    func toRealtimeFormatUsesCorrectModalitiesForText() {
        let session = RealtimeSession(
            model: .gptRealtime,
            outputModality: .text
        )
        
        let format = session.toRealtimeFormat()
        
        guard let modalities = format["modalities"] as? [String] else {
            Issue.record("modalities should be an array of strings")
            return
        }
        
        #expect(modalities == ["text"])
    }
    
    @Test
    func toRealtimeFormatDoesNotUseBothModalities() {
        // Verify that we never send ["text", "audio"] which is invalid per OpenAI docs
        let audioSession = RealtimeSession(model: .gptRealtime, outputModality: .audio)
        let textSession = RealtimeSession(model: .gptRealtime, outputModality: .text)
        
        let audioFormat = audioSession.toRealtimeFormat()
        let textFormat = textSession.toRealtimeFormat()
        
        guard let audioModalities = audioFormat["modalities"] as? [String],
              let textModalities = textFormat["modalities"] as? [String] else {
            Issue.record("modalities should be arrays of strings")
            return
        }
        
        // Neither should contain both "text" and "audio"
        #expect(!(audioModalities.contains("text") && audioModalities.contains("audio")))
        #expect(!(textModalities.contains("text") && textModalities.contains("audio")))
    }
}

