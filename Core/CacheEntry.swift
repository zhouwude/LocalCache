import Foundation

/// Represents a single cache entry with metadata
public struct CacheEntry<Value> {
    /// The cached value
    public let value: Value
    
    /// The timestamp when the entry was created
    public let createdAt: Date
    
    /// The expiration date (nil if never expires)
    public let expiresAt: Date?
    
    /// The cost associated with this entry (for memory cache)
    public let cost: Int
    
    /// Check if the entry has expired
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
    
    /// Check if the entry is still valid
    public var isValid: Bool {
        return !isExpired
    }
    
    /// Time remaining until expiration (nil if never expires)
    public var timeToLive: TimeInterval? {
        guard let expiresAt = expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSinceNow)
    }
    
    /// Initialize a cache entry
    /// - Parameters:
    ///   - value: The value to cache
    ///   - expiration: Optional expiration time interval in seconds
    ///   - cost: Optional cost for memory tracking (defaults to 1)
    public init(_ value: Value, expiration: TimeInterval? = nil, cost: Int = 1) {
        self.value = value
        self.createdAt = Date()
        self.cost = cost
        
        if let expiration = expiration {
            self.expiresAt = Date().addingTimeInterval(expiration)
        } else {
            self.expiresAt = nil
        }
    }
    
    /// Create a new entry with the same value but refreshed timestamp
    public func refresh(expiration: TimeInterval? = nil) -> CacheEntry<Value> {
        return CacheEntry(value, expiration: expiration ?? (expiresAt != nil ? expiresAt!.timeIntervalSince(createdAt) : nil), cost: cost)
    }
}

/// Extension for CacheEntry where Value is Data (for disk cache)
extension CacheEntry where Value == Data {
    /// Create a cache entry from codable object
    public static func fromCodable<T: Codable>(_ value: T, expiration: TimeInterval? = nil, cost: Int = 1) throws -> CacheEntry<Data> {
        let data = try JSONEncoder().encode(value)
        return CacheEntry(data, expiration: expiration, cost: cost)
    }
    
    /// Decode the data to a codable type
    public func decode<T: Codable>(as type: T.Type) throws -> T {
        return try JSONDecoder().decode(T.self, from: value)
    }
}
