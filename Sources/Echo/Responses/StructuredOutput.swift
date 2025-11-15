// StructuredOutput.swift
// Echo - Responses API
// JSON schema support for structured outputs

import Foundation

/// Helper for generating structured outputs using JSON schema
public struct StructuredOutputHelper {
    // MARK: - Schema Generation

    /// Generates a JSON schema from a Codable type
    /// - Parameters:
    ///   - type: The Codable type to generate schema for
    ///   - name: Optional name for the schema
    ///   - explicitSchema: Optional explicit schema definition (recommended for complex types)
    /// - Returns: JSONSchema definition
    public static func generateSchema<T: Codable>(
        for type: T.Type,
        name: String? = nil,
        explicitSchema: [String: AnyCodable]? = nil
    ) -> JSONSchema {
        let schemaName = name ?? String(describing: type)

        // Use explicit schema if provided, otherwise try to build one
        let schema = explicitSchema ?? buildSchema(for: type)

        return JSONSchema(
            name: schemaName,
            strict: true,
            schema: schema
        )
    }

    /// Generates a JSON schema with an explicit properties definition
    /// This is the recommended approach for production use
    /// - Parameters:
    ///   - name: Schema name
    ///   - properties: Property definitions as [propertyName: propertyType]
    ///   - required: List of required property names
    /// - Returns: JSONSchema definition
    public static func generateExplicitSchema(
        name: String,
        properties: [String: PropertyType],
        required: [String]
    ) -> JSONSchema {
        var propsDict: [String: AnyCodable] = [:]

        for (key, propType) in properties {
            propsDict[key] = AnyCodable(propType.toSchemaDict())
        }

        let schema: [String: AnyCodable] = [
            "type": AnyCodable("object"),
            "properties": AnyCodable(propsDict),
            "required": AnyCodable(required),
            "additionalProperties": AnyCodable(false)
        ]

        return JSONSchema(name: name, strict: true, schema: schema)
    }

    /// Builds JSON schema dictionary for a type
    /// WARNING: Mirror on metatypes doesn't work, so we create a default instance and use JSONEncoder
    private static func buildSchema<T: Codable>(for type: T.Type) -> [String: AnyCodable] {
        // Strategy: Use JSONEncoder's ability to encode a type structure
        // We'll encode a sample instance (if possible) to understand the schema

        // Try to create a default instance by decoding minimal JSON
        // This works for many Codable types with default values
        do {
            // Start with empty object and try to decode
            let emptyJSON = "{}".data(using: .utf8)!
            let decoder = JSONDecoder()

            // This will fail for types without default init, but that's expected
            // For those, we fall back to basic schema
            if let instance = try? decoder.decode(type, from: emptyJSON) {
                return try buildSchemaFromInstance(instance)
            }
        } catch {
            // Fall through to basic schema
        }

        // Fallback: return basic object schema
        // Users should provide explicit schemas for complex types
        return [
            "type": AnyCodable("object"),
            "additionalProperties": AnyCodable(false),
            "properties": AnyCodable([:] as [String: Any]),
            "required": AnyCodable([] as [String])
        ]
    }

    /// Builds schema from an actual instance using Mirror
    private static func buildSchemaFromInstance<T>(_ instance: T) throws -> [String: AnyCodable] {
        var schema: [String: AnyCodable] = [
            "type": AnyCodable("object"),
            "additionalProperties": AnyCodable(false)
        ]

        let mirror = Mirror(reflecting: instance)
        var properties: [String: AnyCodable] = [:]
        var required: [String] = []

        for child in mirror.children {
            guard let label = child.label else { continue }

            // Build property schema from actual value
            properties[label] = AnyCodable(buildPropertySchema(for: child.value))
            required.append(label)
        }

        if !properties.isEmpty {
            schema["properties"] = AnyCodable(properties)
            schema["required"] = AnyCodable(required)
        }

        return schema
    }

    /// Builds schema for primitive types
    private static func buildPrimitiveSchema<T>(for type: T.Type) -> [String: AnyCodable] {
        switch type {
        case is String.Type, is String?.Type:
            return ["type": AnyCodable("string")]
        case is Int.Type, is Int?.Type, is Int64.Type, is Int32.Type:
            return ["type": AnyCodable("integer")]
        case is Double.Type, is Double?.Type, is Float.Type:
            return ["type": AnyCodable("number")]
        case is Bool.Type, is Bool?.Type:
            return ["type": AnyCodable("boolean")]
        default:
            return ["type": AnyCodable("object")]
        }
    }

    /// Builds schema for a property
    private static func buildPropertySchema(for value: Any) -> [String: AnyCodable] {
        // Determine type from value
        switch value {
        case is String, is String?:
            return ["type": AnyCodable("string")]
        case is Int, is Int?, is Int64, is Int32:
            return ["type": AnyCodable("integer")]
        case is Double, is Double?, is Float:
            return ["type": AnyCodable("number")]
        case is Bool, is Bool?:
            return ["type": AnyCodable("boolean")]
        case is Array<Any>:
            return [
                "type": AnyCodable("array"),
                "items": AnyCodable(["type": AnyCodable("object")])
            ]
        default:
            return ["type": AnyCodable("object")]
        }
    }
}

// MARK: - Property Type Definition

/// Represents a JSON schema property type
public indirect enum PropertyType {
    case string(description: String? = nil)
    case integer(description: String? = nil)
    case number(description: String? = nil)
    case boolean(description: String? = nil)
    case array(items: PropertyType, description: String? = nil)
    case object(properties: [String: PropertyType], required: [String], description: String? = nil)

    func toSchemaDict() -> [String: Any] {
        switch self {
        case .string(let description):
            var dict: [String: Any] = ["type": "string"]
            if let desc = description { dict["description"] = desc }
            return dict

        case .integer(let description):
            var dict: [String: Any] = ["type": "integer"]
            if let desc = description { dict["description"] = desc }
            return dict

        case .number(let description):
            var dict: [String: Any] = ["type": "number"]
            if let desc = description { dict["description"] = desc }
            return dict

        case .boolean(let description):
            var dict: [String: Any] = ["type": "boolean"]
            if let desc = description { dict["description"] = desc }
            return dict

        case .array(let items, let description):
            var dict: [String: Any] = [
                "type": "array",
                "items": items.toSchemaDict()
            ]
            if let desc = description { dict["description"] = desc }
            return dict

        case .object(let properties, let required, let description):
            var propsDict: [String: Any] = [:]
            for (key, value) in properties {
                propsDict[key] = value.toSchemaDict()
            }
            var dict: [String: Any] = [
                "type": "object",
                "properties": propsDict,
                "required": required
            ]
            if let desc = description { dict["description"] = desc }
            return dict
        }
    }
}

// MARK: - Structured Output Extension for ResponsesClient

extension ResponsesClient {
    /// Generates a structured output by providing a JSON schema
    /// - Parameters:
    ///   - prompt: The prompt to send
    ///   - schema: The expected output type
    ///   - model: The model to use (MUST be gpt-5, gpt-5-mini, or gpt-5-nano)
    ///   - instructions: Optional system instructions
    /// - Returns: Decoded instance of T
    /// - Throws: ResponsesError if generation or decoding fails
    public func generateStructured<T: Codable>(
        prompt: String,
        schema: T.Type,
        model: ResponsesModel,
        instructions: String? = nil
    ) async throws -> T {
        // Generate JSON schema
        let jsonSchema = StructuredOutputHelper.generateSchema(for: schema)

        // Convert to API format
        let apiMessage = InputMessage(role: "user", content: prompt)

        // Build request with response_format
        let request = ResponsesRequest(
            model: model.rawValue,
            input: .messages([apiMessage]),
            instructions: instructions,
            responseFormat: .jsonSchema(jsonSchema),
            stream: false
        )

        // Execute request
        let response: ResponsesResponse = try await httpClient.request(
            endpoint: "/responses",
            method: .POST,
            body: request,
            estimatedTokens: 2000
        )

        // Extract JSON from response
        guard let jsonText = response.firstText else {
            throw ResponsesError.structuredOutputFailed("No output received")
        }

        // Decode JSON to target type
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw ResponsesError.structuredOutputFailed("Invalid UTF-8 in response")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: jsonData)
        } catch {
            throw ResponsesError.decodingError(error)
        }
    }

    /// Generates a structured output with a custom JSON schema
    /// - Parameters:
    ///   - prompt: The prompt to send
    ///   - jsonSchema: Custom JSON schema definition
    ///   - model: The model to use
    ///   - instructions: Optional system instructions
    /// - Returns: Raw JSON string
    /// - Throws: ResponsesError if generation fails
    public func generateStructuredJSON(
        prompt: String,
        jsonSchema: JSONSchema,
        model: ResponsesModel,
        instructions: String? = nil
    ) async throws -> String {
        // Convert message
        let apiMessage = InputMessage(role: "user", content: prompt)

        // Build request
        let request = ResponsesRequest(
            model: model.rawValue,
            input: .messages([apiMessage]),
            instructions: instructions,
            responseFormat: .jsonSchema(jsonSchema),
            stream: false
        )

        // Execute request
        let response: ResponsesResponse = try await httpClient.request(
            endpoint: "/responses",
            method: .POST,
            body: request,
            estimatedTokens: 2000
        )

        guard let jsonText = response.firstText else {
            throw ResponsesError.structuredOutputFailed("No output received")
        }

        return jsonText
    }
}

// MARK: - Example Usage
/*
 Example usage of structured outputs:

 ```swift
 // Define your output structure
 struct UserProfile: Codable {
     let name: String
     let age: Int
     let email: String
     let interests: [String]
 }

 // Generate structured output
 let client = ResponsesClient(apiKey: "sk-...")
 let profile: UserProfile = try await client.generateStructured(
     prompt: "Extract: John Doe, 28, john@example.com, loves hiking and photography",
     schema: UserProfile.self,
     model: .gpt5
 )

 print(profile.name) // "John Doe"
 print(profile.age)  // 28
 ```
 */
