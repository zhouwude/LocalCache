import Foundation
import os.log

/// Hybrid cache combining memory and disk storage
public final class HybridCache<Key: Hashable, Value: Codable>: CacheProtocol {
    public typealias KeyType = Key
    public typealias ValueType = Value
    
    private let memoryCache: MemoryCache<Key, Value>?
    private let diskCache: DiskCache<Key, Value>?
    private let configuration: CacheConfiguration
    private let asyncQueue: DispatchQueue
    
    /// Current number of items (memory + disk)
    public var count: Int {
        get async throws {
            async let memCount = memoryCache?.count ?? 0
            async let diskCount = diskCache?.count ?? 0
            return (try await memCount) + (try await diskCount)
        }
    }
    
    /// Initialize hybrid cache
    /// - Parameter configuration: Cache configuration
    public init(configuration: CacheConfiguration = .hybridCache()) {
        self.configuration = configuration

        if configuration.enableMemoryCache {
            self.memoryCache = MemoryCache(configuration: configuration)
        } else {
            self.memoryCache = nil
        }

        if configuration.enableDiskCache {
            self.diskCache = DiskCache(configuration: configuration)
        } else {
            self.diskCache = nil
        }

        self.asyncQueue = DispatchQueue(
            label: "com.localcache.hybrid.async",
            qos: configuration.queuePriority,
            attributes: .concurrent
        )
    }

    /// Log disk write errors (called from background task)
    private static func logDiskWriteError(_ error: any Error) {
        #if DEBUG
        print("[HybridCache] Disk persistence failed: \(error.localizedDescription)")
        print("[HybridCache] Data will not survive app restart")
        #else
        os_log("[HybridCache] Disk persistence failed: %{public}@. Data will not survive app restart.",
               log: .default, type: .error, error.localizedDescription)
        #endif
    }
    
    /// Prepare the cache (call once after initialization)
    public func prepare() async throws {
        try await diskCache?.prepare()
    }
    
    /// Store a value with the given key
    /// - Parameters:
    ///   - value: The value to store
    ///   - key: The key
    ///   - expiration: Optional expiration time in seconds
    public func set(_ value: Value, forKey key: Key, expiration: TimeInterval? = nil) async throws {
        // Write to memory cache first (fast path)
        if let memoryCache = memoryCache {
            try await memoryCache.set(value, forKey: key, expiration: expiration)
        }
        
        // Write to disk cache asynchronously (background persistence)
        if let diskCache = diskCache {
            Task.detached(priority: .background) { [weak self] in
                guard self != nil else { return }
                do {
                    try await diskCache.set(value, forKey: key, expiration: expiration)
                } catch is CancellationError {
                    // Task was cancelled, silently ignore
                    return
                } catch {
                    // Log disk write errors for observability
                    // Memory cache write succeeded, so caller sees success
                    // but disk persistence failure means data won't survive app restart
                    Self.logDiskWriteError(error)
                }
            }
        }
    }
    
    /// Retrieve a value for the given key
    /// - Parameter key: The key
    /// - Returns: The cached value or nil
    public func get(forKey key: Key) async throws -> Value? {
        // Try memory cache first (fast path)
        if let memoryCache = memoryCache {
            if let value = try await memoryCache.get(forKey: key) {
                return value
            }
        }
        
        // Fall back to disk cache
        if let diskCache = diskCache {
            if let value = try await diskCache.get(forKey: key) {
                // Promote to memory cache
                if let memoryCache = memoryCache {
                    try? await memoryCache.set(value, forKey: key)
                }
                return value
            }
        }
        
        return nil
    }
    
    /// Remove a value for the given key
    /// - Parameter key: The key
    public func remove(forKey key: Key) async throws {
        // Remove from both caches
        try? await memoryCache?.remove(forKey: key)
        try? await diskCache?.remove(forKey: key)
    }
    
    /// Remove all cached values
    public func removeAll() async throws {
        try? await memoryCache?.removeAll()
        try? await diskCache?.removeAll()
    }
    
    /// Check if a key exists in the cache
    /// - Parameter key: The key
    /// - Returns: true if exists and not expired
    public func contains(forKey key: Key) async throws -> Bool {
        // Check memory cache first
        if let memoryCache = memoryCache {
            if try await memoryCache.contains(forKey: key) {
                return true
            }
        }
        
        // Check disk cache
        if let diskCache = diskCache {
            return try await diskCache.contains(forKey: key)
        }
        
        return false
    }
    
    /// Remove expired entries
    public func cleanupExpired() async throws {
        try? await memoryCache?.cleanupExpired()
        try? await diskCache?.cleanupExpired()
    }
    
    /// Flush memory cache to disk (force persistence)
    public func flush() async throws {
        guard let memoryCache = memoryCache, let diskCache = diskCache else { return }
        
        let keys = try await memoryCache.allKeys()
        for key in keys {
            if let value = try await memoryCache.get(forKey: key) {
                try await diskCache.set(value, forKey: key)
            }
        }
    }
    
    /// Invalidate disk cache (force reload from source)
    public func invalidateDisk() async throws {
        try await diskCache?.removeAll()
    }
    
    /// Get cache statistics
    public var statistics: CacheStatistics {
        get async throws {
            async let memCountTask: Int = memoryCache?.count ?? 0
            async let diskCountTask: Int = diskCache?.count ?? 0
            async let diskSizeTask: Int64 = diskCache?.totalSize ?? 0
            async let memStats: CacheStatsSnapshot? = memoryCache?.stats
            
            return CacheStatistics(
                memoryCount: try await memCountTask,
                diskCount: try await diskCountTask,
                diskSizeBytes: try await diskSizeTask,
                memoryStats: try await memStats
            )
        }
    }
}

/// Cache statistics
public struct CacheStatistics {
    public let memoryCount: Int
    public let diskCount: Int
    public let diskSizeBytes: Int64
    public let memoryStats: CacheStatsSnapshot?
    
    public var totalCount: Int {
        return memoryCount + diskCount
    }
    
    public var diskSizeMB: Double {
        return Double(diskSizeBytes) / 1024.0 / 1024.0
    }
    
    public var hitRate: Double {
        return memoryStats?.hitRate ?? 0.0
    }
    
    public var hitRatePercentage: Double {
        return (memoryStats?.hitRate ?? 0.0) * 100.0
    }
}

// MARK: - Convenience Methods

extension HybridCache {
    /// Get or set a value with a factory
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
