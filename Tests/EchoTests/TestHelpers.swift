// TestHelpers.swift
// Echo Tests
// Helper utilities for testing

import Foundation
import XCTest

/// Loads the OpenAI API key from environment or .env file
func loadAPIKey() -> String? {
    // First, check ProcessInfo environment
    if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
        return key
    }

    // If not in environment, try to load from .env file in package root
    let possiblePaths = [
        FileManager.default.currentDirectoryPath + "/.env",
        FileManager.default.currentDirectoryPath + "/../../.env"
    ]

    for envPath in possiblePaths {
        guard let envContents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            continue
        }

        // Parse .env file for OPENAI_API_KEY
        for line in envContents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("OPENAI_API_KEY=") {
                let key = trimmed.replacingOccurrences(of: "OPENAI_API_KEY=", with: "")
                let cleanKey = key.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !cleanKey.isEmpty {
                    return cleanKey
                }
            }
        }
    }

    return nil
}