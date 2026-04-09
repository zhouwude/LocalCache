import Foundation

/// Manages disk cache storage and cleanup
public final class DiskCacheManager {
    private let storage: FileStorage
    private let configuration: CacheConfiguration
    private let lock: Lock
    
    /// Metadata file name
    private let metadataFileName = "cache_metadata.json"
    
    /// Initialize disk cache manager
    /// - Parameters:
    ///   - configuration: Cache configuration
    public init(configuration: CacheConfiguration) {
        let directory = configuration.storageDirectory ?? {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            return caches.appendingPathComponent("LocalCache", isDirectory: true)
        }()
        
        self.storage = FileStorage(
            directory: directory,
            maxFileSize: configuration.maxDiskCacheSize / 10
        )
        self.configuration = configuration
        self.lock = Lock()
    }
    
    /// Initialize with custom storage
    /// - Parameters:
    ///   - storage: File storage instance
    ///   - configuration: Cache configuration
    public init(storage: FileStorage, configuration: CacheConfiguration) {
        self.storage = storage
        self.configuration = configuration
        self.lock = Lock()
    }
    
    /// Ensure storage is ready
    public func prepare() throws {
        try storage.ensureDirectory()
    }
    
    /// Write data to disk
    /// - Parameters:
    ///   - data: The data to write
    ///   - key: The key (used as filename)
    public func write(_ data: Data, forKey key: String) async throws {
        try await storage.write(data, fileName: safeFileName(from: key))
    }
    
    /// Read data from disk
    /// - Parameter key: The key
    /// - Returns: The data or nil
    public func read(forKey key: String) async throws -> Data? {
        return try await storage.read(fileName: safeFileName(from: key))
    }
    
    /// Remove data from disk
    /// - Parameter key: The key
    public func remove(forKey key: String) throws {
        try storage.remove(fileName: safeFileName(from: key))
    }
    
    /// Remove all data
    public func removeAll() throws {
        try storage.removeAll()
    }
    
    /// Check if key exists
    /// - Parameter key: The key
    /// - Returns: true if exists
    public func contains(forKey key: String) -> Bool {
        return storage.fileExists(fileName: safeFileName(from: key))
    }
    
    /// Get total disk usage
    /// - Returns: Total size in bytes
    public var totalSize: Int64 {
        return storage.totalSize
    }
    
    /// Check if cache is full
    /// - Returns: true if over limit
    public var isFull: Bool {
        return totalSize >= configuration.maxDiskCacheSize
    }
    
    /// Cleanup to fit within size limit
    /// - Parameter metadata: Cache metadata for LRU tracking
    public func cleanup(metadata: inout DiskCacheMetadata) async throws {
        guard isFull else { return }
        
        // Sort by last access time
        metadata.accessOrder.sort { key1, key2 in
            (metadata.lastAccess[key1] ?? .distantPast) > 
            (metadata.lastAccess[key2] ?? .distantPast)
        }
        
        var currentSize = totalSize
        let targetSize = Int64(Double(configuration.maxDiskCacheSize) * 0.8)
        
        while currentSize > targetSize, let oldestKey = metadata.accessOrder.popLast() {
            let fileName = safeFileName(from: oldestKey)
            if let fileSize = storage.fileSize(fileName: fileName) {
                try storage.remove(fileName: fileName)
                currentSize -= fileSize
                metadata.lastAccess.removeValue(forKey: oldestKey)
                metadata.entries.removeValue(forKey: oldestKey)
            }
        }
    }
    
    /// Load metadata
    /// - Returns: Cache metadata
    public func loadMetadata() async throws -> DiskCacheMetadata {
        guard let data = try await storage.read(fileName: metadataFileName),
              let metadata = try? JSONDecoder().decode(DiskCacheMetadata.self, from: data) else {
            return DiskCacheMetadata()
        }
        return metadata
    }
    
    /// Save metadata
    /// - Parameter metadata: Cache metadata
    public func saveMetadata(_ metadata: DiskCacheMetadata) async throws {
        let data = try JSONEncoder().encode(metadata)
        try await storage.write(data, fileName: metadataFileName)
    }
    
    /// Get safe file name from key
    /// - Parameter key: The cache key
    /// - Returns: Safe file name
    private func safeFileName(from key: String) -> String {
        // Use MD5 or base64 encoding for safe file names
        let data = Data(key.utf8)
        return data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }
}

/// Metadata for disk cache
public struct DiskCacheMetadata: Codable {
    /// Map of key to entry metadata
    public var entries: [String: EntryMetadata]
    
    /// Access order for LRU (front = most recent)
    public var accessOrder: [String]
    
    /// Last access time for each key
    public var lastAccess: [String: Date]
    
    public init() {
        self.entries = [:]
        self.accessOrder = []
        self.lastAccess = [:]
    }
    
    /// Entry metadata
    public struct EntryMetadata: Codable {
        public let createdAt: Date
        public let expiresAt: Date?
        public let size: Int64
        
        public init(createdAt: Date, expiresAt: Date?, size: Int64) {
            self.createdAt = createdAt
            self.expiresAt = expiresAt
            self.size = size
        }
    }
}
