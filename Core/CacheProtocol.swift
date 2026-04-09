import Foundation

/// Cache operation protocol defining the basic interface for all cache implementations
public protocol CacheProtocol: AnyObject {
    associatedtype Key: Hashable
    associatedtype Value
    
    /// Store a value with the given key
    /// - Parameters:
    ///   - value: The value to store
    ///   - key: The key to associate with the value
    ///   - expiration: Optional expiration time interval (in seconds)
    func set(_ value: Value, forKey key: Key, expiration: TimeInterval?) async throws
    
    /// Retrieve a value for the given key
    /// - Parameter key: The key to look up
    /// - Returns: The cached value, or nil if not found or expired
    func get(forKey key: Key) async throws -> Value?
    
    /// Remove a value for the given key
    /// - Parameter key: The key to remove
    func remove(forKey key: Key) async throws
    
    /// Remove all cached values
    func removeAll() async throws
    
    /// Check if a key exists in the cache
    /// - Parameter key: The key to check
    /// - Returns: true if the key exists and is not expired
    func contains(forKey key: Key) async throws -> Bool
    
    /// Get the count of items in the cache
    var count: Int { get async throws }
    
    /// Remove expired entries
    func cleanupExpired() async throws
}

/// Extended protocol for caches that support memory cost tracking
public protocol CostableCache: CacheProtocol {
    /// Get the total cost of all cached items
    var totalCost: Int { get async throws }
    
    /// Set the maximum cost limit
    var maxCost: Int { get set }
}

/// Extended protocol for caches that support observation
public protocol ObservableCache: CacheProtocol {
    associatedtype Observer
    
    /// Add an observer for cache events
    func addObserver(_ observer: Observer) async throws
    
    /// Remove an observer
    func removeObserver(_ observer: Observer) async throws
}
