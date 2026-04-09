import Foundation

/// Configuration for cache behavior
public struct CacheConfiguration {
    /// Maximum number of items to store (for memory cache)
    public var maxItemCount: Int
    
    /// Maximum total cost (for memory cache with cost tracking)
    public var maxTotalCost: Int
    
    /// Default expiration time in seconds (0 = never expire)
    public var defaultExpiration: TimeInterval
    
    /// Whether to cleanup expired entries on access
    public var autoCleanup: Bool
    
    /// Directory for disk cache storage
    public var storageDirectory: URL?
    
    /// Maximum disk cache size in bytes
    public var maxDiskCacheSize: Int64
    
    /// Whether to use memory cache in hybrid mode
    public var enableMemoryCache: Bool
    
    /// Whether to use disk cache in hybrid mode
    public var enableDiskCache: Bool
    
    /// Queue priority for async operations
    public var queuePriority: DispatchQoS
    
    /// Initialize cache configuration
    /// - Parameters:
    ///   - maxItemCount: Maximum number of items (default: 100)
    ///   - maxTotalCost: Maximum total cost (default: 1000)
    ///   - defaultExpiration: Default expiration in seconds (default: 0 = never)
    ///   - autoCleanup: Whether to auto cleanup expired entries (default: true)
    ///   - storageDirectory: Directory for disk cache (default: caches directory)
    ///   - maxDiskCacheSize: Maximum disk cache size in bytes (default: 100MB)
    ///   - enableMemoryCache: Enable memory cache (default: true)
    ///   - enableDiskCache: Enable disk cache (default: true)
    ///   - queuePriority: Dispatch queue priority (default: .utility)
    public init(
        maxItemCount: Int = 100,
        maxTotalCost: Int = 1000,
        defaultExpiration: TimeInterval = 0,
        autoCleanup: Bool = true,
        storageDirectory: URL? = nil,
        maxDiskCacheSize: Int64 = 100 * 1024 * 1024, // 100MB
        enableMemoryCache: Bool = true,
        enableDiskCache: Bool = true,
        queuePriority: DispatchQoS = .utility
    ) {
        self.maxItemCount = maxItemCount
        self.maxTotalCost = maxTotalCost
        self.defaultExpiration = defaultExpiration
        self.autoCleanup = autoCleanup
        self.storageDirectory = storageDirectory
        self.maxDiskCacheSize = maxDiskCacheSize
        self.enableMemoryCache = enableMemoryCache
        self.enableDiskCache = enableDiskCache
        self.queuePriority = queuePriority
    }
    
    /// Create a configuration optimized for memory cache
    public static func memoryCache(maxItems: Int = 100, maxCost: Int = 1000) -> CacheConfiguration {
        return CacheConfiguration(
            maxItemCount: maxItems,
            maxTotalCost: maxCost,
            enableMemoryCache: true,
            enableDiskCache: false
        )
    }
    
    /// Create a configuration optimized for disk cache
    public static func diskCache(maxSize: Int64 = 100 * 1024 * 1024, directory: URL? = nil) -> CacheConfiguration {
        return CacheConfiguration(
            storageDirectory: directory,
            maxDiskCacheSize: maxSize,
            enableMemoryCache: false,
            enableDiskCache: true
        )
    }
    
    /// Create a configuration for hybrid cache
    public static func hybridCache(
        memoryItems: Int = 50,
        diskSize: Int64 = 100 * 1024 * 1024
    ) -> CacheConfiguration {
        return CacheConfiguration(
            maxItemCount: memoryItems,
            maxTotalCost: memoryItems,
            maxDiskCacheSize: diskSize,
            enableMemoryCache: true,
            enableDiskCache: true
        )
    }
}
