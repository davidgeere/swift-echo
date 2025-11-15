import Foundation

/// Reasoning effort level for controlling the depth of model reasoning
public enum ReasoningEffort: String, Codable, Sendable {
    /// Low reasoning effort - quick responses with minimal reasoning
    case low = "low"
    
    /// Medium reasoning effort - balanced reasoning and response time
    case medium = "medium"
    
    /// High reasoning effort - thorough reasoning for complex problems
    case high = "high"
    
    /// No explicit reasoning - disables reasoning output; model provides direct answers without reasoning steps (default)
    case none = "none"
}
