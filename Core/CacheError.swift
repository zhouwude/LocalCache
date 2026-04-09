import Foundation

/// Cache-related errors
public enum CacheError: LocalizedError {
    /// The requested key was not found in the cache
    case notFound(String)
    
    /// The cache entry has expired
    case expired(String)
    
    /// Failed to encode/decode cache data
    case encodingFailed(String)
    
    /// Failed to read/write disk cache
    case diskIOError(String)
    
    /// Cache storage is full
    case storageFull
    
    /// Invalid configuration
    case invalidConfiguration(String)
    
    /// Operation was cancelled
    case cancelled
    
    /// Unknown error
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .notFound(let key):
            return "Key '\(key)' not found in cache"
        case .expired(let key):
            return "Cache entry for key '\(key)' has expired"
        case .encodingFailed(let reason):
            return "Encoding/decing failed: \(reason)"
        case .diskIOError(let reason):
            return "Disk I/O error: \(reason)"
        case .storageFull:
            return "Cache storage is full"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .cancelled:
            return "Operation was cancelled"
        case .unknown(let reason):
            return "Unknown error: \(reason)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .notFound, .expired:
            return "Try setting a new value for this key"
        case .encodingFailed:
            return "Ensure your data conforms to Codable protocol"
        case .diskIOError:
            return "Check disk permissions and available space"
        case .storageFull:
            return "Try removing old entries or increasing cache capacity"
        case .invalidConfiguration:
            return "Review cache configuration parameters"
        case .cancelled:
            return "Retry the operation"
        case .unknown:
            return "Check logs for more details"
        }
    }
}

/// Result type for cache operations
public typealias CacheResult<Value> = Result<Value, CacheError>

/// Async throwing function helper
public typealias CacheThrowing<Value> = () async throws -> Value
