import Foundation

/// Thread-safe in-memory cache implementation
public final class MemoryCache<Key: Hashable, Value>: CacheProtocol, CostableCache {
    public typealias KeyType = Key
    public typealias ValueType = Value
    
    private let lruCache: LRUCache<Key, Value>
    private let configuration: CacheConfiguration
    private var observers: [Any] = []
    private let observerLock: Lock
    
    /// Statistics tracker for monitoring cache performance
    public let statisticsTracker: CacheStatisticsTracker
    
    /// Current number of items
    public var count: Int {
        get async throws { lruCache.count }
    }
    
    /// Total cost of cached items
    public var totalCost: Int {
        get async throws { lruCache.totalCost }
    }
    
    /// Maximum cost limit
    public var maxCost: Int {
        get { lruCache.maxTotalCost }
        set { /* Immutable after init */ }
    }
    
    /// Initialize memory cache
    /// - Parameter configuration: Cache configuration
    public init(configuration: CacheConfiguration = .memoryCache()) {
        self.configuration = configuration
        self.lruCache = LRUCache(
            maxItemCount: configuration.maxItemCount,
            maxTotalCost: configuration.maxTotalCost
        )
        self.observerLock = Lock()
        self.statisticsTracker = CacheStatisticsTracker()
    }
    
    /// Store a value with the given key
    /// - Parameters:
    ///   - value: The value to store
    ///   - key: The key
    ///   - expiration: Optional expiration time in seconds
    public func set(_ value: Value, forKey key: Key, expiration: TimeInterval? = nil) async throws {
        let exp = expiration ?? configuration.defaultExpiration
        let entry = CacheEntry(value, expiration: exp)
        let evicted = lruCache.insert(entry, forKey: key)
        
        statisticsTracker.recordWrite()
        if evicted != nil {
            statisticsTracker.recordEviction()
        }
        
        await notifyObservers(.set(key: key))
    }
    
    /// Retrieve a value for the given key
    /// - Parameter key: The key
    /// - Returns: The cached value or nil
    public func get(forKey key: Key) async throws -> Value? {
        guard let entry = lruCache.access(forKey: key) else {
            statisticsTracker.recordMiss()
            await notifyObservers(.miss(key: key))
            return nil
        }
        
        if entry.isExpired {
            statisticsTracker.recordMiss()
            try await remove(forKey: key)
            await notifyObservers(.expired(key: key))
            return nil
        }
        
        statisticsTracker.recordHit()
        await notifyObservers(.hit(key: key))
        return entry.value
    }
    
    /// Remove a value for the given key
    /// - Parameter key: The key
    public func remove(forKey key: Key) async throws {
        let removed = lruCache.remove(forKey: key)
        if removed != nil {
            statisticsTracker.recordRemove()
        }
        await notifyObservers(.remove(key: key))
    }
    
    /// Remove all cached values
    public func removeAll() async throws {
        lruCache.removeAll()
        await notifyObservers(.clear)
    }
    
    /// Check if a key exists in the cache
    /// - Parameter key: The key
    /// - Returns: true if exists and not expired
    public func contains(forKey key: Key) async throws -> Bool {
        return lruCache.contains(forKey: key)
    }
    
    /// Remove expired entries
    public func cleanupExpired() async throws {
        let removed = lruCache.cleanupExpired()
        if removed > 0 {
            statisticsTracker.recordEvictions(removed)
            await notifyObservers(.cleanup(count: removed))
        }
    }
    
    /// Get all keys
    public func allKeys() async throws -> [Key] {
        return lruCache.allKeys
    }
    
    /// Get current statistics snapshot
    public var stats: CacheStatsSnapshot {
        return statisticsTracker.snapshot
    }
    
    // MARK: - Observer Pattern
    
    public enum ObserverEvent {
        case set(key: Key)
        case miss(key: Key)
        case hit(key: Key)
        case remove(key: Key)
        case expired(key: Key)
        case clear
        case cleanup(count: Int)
    }
    
    public typealias ObserverCallback = (ObserverEvent) async -> Void
    
    private var observerCallbacks: [UUID: ObserverCallback] = [:]
    
    /// Add an observer
    /// - Parameter callback: The callback to invoke on events
    /// - Returns: Observer ID
    public func addObserver(_ callback: @escaping ObserverCallback) -> UUID {
        observerLock.sync {
            let id = UUID()
            observerCallbacks[id] = callback
            return id
        }
    }
    
    /// Remove an observer
    /// - Parameter id: The observer ID
    public func removeObserver(_ id: UUID) {
        observerLock.sync {
            observerCallbacks.removeValue(forKey: id)
        }
    }
    
    private func notifyObservers(_ event: ObserverEvent) {
        observerLock.sync {
            for callback in observerCallbacks.values {
                Task { @Sendable in
                    await callback(event)
                }
            }
        }
    }
}

// MARK: - Convenience Methods

extension MemoryCache {
    /// Get or set a value with a factory
    /// - Parameters:
    ///   - key: The key
    ///   - factory: Factory to create value if not cached
    ///   - expiration: Optional expiration
    /// - Returns: The cached or newly created value
    public func getOrSet(
        forKey key: Key,
        factory: () async throws -> Value,
        expiration: TimeInterval? = nil
    ) async throws -> Value {
        if let cached = try await get(forKey: key) {
            return cached
        }
        
        let value = try await factory()
        try await set(value, forKey: key, expiration: expiration)
        return value
    }
}
