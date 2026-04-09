import Foundation

/// Disk-based cache implementation
public final class DiskCache<Key: Hashable, Value: Codable>: CacheProtocol {
    public typealias KeyType = Key
    public typealias ValueType = Value
    
    private let manager: DiskCacheManager
    private var metadata: DiskCacheMetadata
    private let configuration: CacheConfiguration
    private let metadataLock: Lock
    
    /// Current number of items
    public var count: Int {
        get async throws {
            metadataLock.sync { metadata.entries.count }
        }
    }
    
    /// Total disk usage in bytes
    public var totalSize: Int64 {
        manager.totalSize
    }
    
    /// Initialize disk cache
    /// - Parameter configuration: Cache configuration
    public init(configuration: CacheConfiguration = .diskCache()) {
        self.configuration = configuration
        self.manager = DiskCacheManager(configuration: configuration)
        self.metadata = DiskCacheMetadata()
        self.metadataLock = Lock()
    }
    
    /// Prepare the cache (call once after initialization)
    public func prepare() async throws {
        try manager.prepare()
    }
    
    /// Store a value with the given key
    /// - Parameters:
    ///   - value: The value to store (must be Codable)
    ///   - key: The key
    ///   - expiration: Optional expiration time in seconds
    public func set(_ value: Value, forKey key: Key, expiration: TimeInterval? = nil) async throws {
        let keyString = keyToString(key)
        let exp = expiration ?? configuration.defaultExpiration
        
        // Encode value
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw CacheError.encodingFailed(error.localizedDescription)
        }
        
        // Write to disk
        try await manager.write(data, forKey: keyString)
        
        // Update metadata
        metadataLock.sync {
            let entryMeta = DiskCacheMetadata.EntryMetadata(
                createdAt: Date(),
                expiresAt: exp > 0 ? Date().addingTimeInterval(exp) : nil,
                size: Int64(data.count)
            )
            metadata.entries[keyString] = entryMeta
            
            // Update access order
            if let index = metadata.accessOrder.firstIndex(of: keyString) {
                metadata.accessOrder.remove(at: index)
            }
            metadata.accessOrder.append(keyString)
            metadata.lastAccess[keyString] = Date()
        }
        
        // Cleanup if needed
        if manager.isFull {
            try await manager.cleanup(metadata: &metadata)
        }
        
        // Save metadata
        try? await manager.saveMetadata(metadata)
    }
    
    /// Retrieve a value for the given key
    /// - Parameter key: The key
    /// - Returns: The cached value or nil
    public func get(forKey key: Key) async throws -> Value? {
        let keyString = keyToString(key)
        
        // Check metadata
        guard let entryMeta = metadataLock.sync({ metadata.entries[keyString] }) else {
            return nil
        }
        
        // Check expiration
        if let expiresAt = entryMeta.expiresAt, Date() > expiresAt {
            try await remove(forKey: key)
            return nil
        }
        
        // Read from disk
        guard let data = try await manager.read(forKey: keyString) else {
            metadataLock.sync {
                metadata.entries.removeValue(forKey: keyString)
            }
            return nil
        }
        
        // Update access time
        metadataLock.sync {
            metadata.lastAccess[keyString] = Date()
            if let index = metadata.accessOrder.firstIndex(of: keyString) {
                metadata.accessOrder.remove(at: index)
            }
            metadata.accessOrder.append(keyString)
        }
        
        // Decode value
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw CacheError.encodingFailed(error.localizedDescription)
        }
    }
    
    /// Remove a value for the given key
    /// - Parameter key: The key
    public func remove(forKey key: Key) async throws {
        let keyString = keyToString(key)
        try manager.remove(forKey: keyString)
        
        metadataLock.sync {
            metadata.entries.removeValue(forKey: keyString)
            metadata.accessOrder.removeAll { $0 == keyString }
            metadata.lastAccess.removeValue(forKey: keyString)
        }
        
        try? await manager.saveMetadata(metadata)
    }
    
    /// Remove all cached values
    public func removeAll() async throws {
        try manager.removeAll()
        
        metadataLock.sync {
            metadata = DiskCacheMetadata()
        }
        
        try? await manager.saveMetadata(metadata)
    }
    
    /// Check if a key exists in the cache
    /// - Parameter key: The key
    /// - Returns: true if exists and not expired
    public func contains(forKey key: Key) async throws -> Bool {
        let keyString = keyToString(key)
        
        guard let entryMeta = metadataLock.sync({ metadata.entries[keyString] }) else {
            return false
        }
        
        // Check expiration
        if let expiresAt = entryMeta.expiresAt, Date() > expiresAt {
            try await remove(forKey: key)
            return false
        }
        
        return manager.contains(forKey: keyString)
    }
    
    /// Remove expired entries
    public func cleanupExpired() async throws {
        var expiredKeys: [String] = []
        
        metadataLock.sync {
            expiredKeys = metadata.entries.compactMap { key, meta in
                if let expiresAt = meta.expiresAt, Date() > expiresAt {
                    return key
                }
                return nil
            }
        }
        
        for keyString in expiredKeys {
            try manager.remove(forKey: keyString)
            
            metadataLock.sync {
                metadata.entries.removeValue(forKey: keyString)
                metadata.accessOrder.removeAll { $0 == keyString }
                metadata.lastAccess.removeValue(forKey: keyString)
            }
        }
        
        if !expiredKeys.isEmpty {
            try? await manager.saveMetadata(metadata)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Convert key to string
    private func keyToString(_ key: Key) -> String {
        if let stringKey = key as? String {
            return stringKey
        } else if let codableKey = key as? any Codable {
            do {
                let data = try JSONEncoder().encode(codableKey)
                return String(data: data, encoding: .utf8) ?? String(describing: key)
            } catch {
                return String(describing: key)
            }
        } else {
            return String(describing: key)
        }
    }
}

// MARK: - Convenience Methods

extension DiskCache {
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
