import Foundation

/// Low-level file storage manager
public final class FileStorage {
    private let directory: URL
    private let fileManager: FileManager
    private let lock: Lock
    private let maxFileSize: Int64
    
    /// Initialize file storage
    /// - Parameters:
    ///   - directory: The directory URL
    ///   - maxFileSize: Maximum file size in bytes
    public init(directory: URL, maxFileSize: Int64 = 10 * 1024 * 1024) {
        self.directory = directory
        self.fileManager = FileManager.default
        self.lock = Lock()
        self.maxFileSize = maxFileSize
    }
    
    /// Ensure the storage directory exists
    public func ensureDirectory() throws {
        try lock.sync {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
        }
    }
    
    /// Write data to a file
    /// - Parameters:
    ///   - data: The data to write
    ///   - fileName: The file name
    /// - Throws: CacheError if write fails
    public func write(_ data: Data, fileName: String) async throws {
        try ensureDirectory()
        
        let fileURL = directory.appendingPathComponent(fileName)
        
        // Check file size
        if Int64(data.count) > maxFileSize {
            throw CacheError.storageFull
        }
        
        try await AsyncIO.write(to: fileURL, data: data)
    }
    
    /// Read data from a file
    /// - Parameter fileName: The file name
    /// - Returns: The data, or nil if file doesn't exist
    public func read(fileName: String) async throws -> Data? {
        try ensureDirectory()
        
        let fileURL = directory.appendingPathComponent(fileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        return try await AsyncIO.read(from: fileURL)
    }
    
    /// Check if a file exists
    /// - Parameter fileName: The file name
    /// - Returns: true if exists
    public func fileExists(fileName: String) -> Bool {
        let fileURL = directory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    /// Remove a file
    /// - Parameter fileName: The file name
    public func remove(fileName: String) throws {
        try lock.sync {
            let fileURL = directory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }
    
    /// Remove all files
    public func removeAll() throws {
        try lock.sync {
            if fileManager.fileExists(atPath: directory.path) {
                let contents = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                for fileURL in contents {
                    try fileManager.removeItem(at: fileURL)
                }
            }
        }
    }
    
    /// Get file size
    /// - Parameter fileName: The file name
    /// - Returns: File size in bytes, or nil if doesn't exist
    public func fileSize(fileName: String) -> Int64? {
        let fileURL = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }
    
    /// Get total size of all files
    /// - Returns: Total size in bytes
    public var totalSize: Int64 {
        lock.sync {
            guard fileManager.fileExists(atPath: directory.path) else { return 0 }
            
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: []
                )
                
                return contents.compactMap { url -> Int64 in
                    Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                .reduce(0, +)
            } catch {
                return 0
            }
        }
    }
    
    /// Get all file names
    /// - Returns: Array of file names
    public var allFileNames: [String] {
        lock.sync {
            guard fileManager.fileExists(atPath: directory.path) else { return [] }
            
            do {
                return try fileManager.contentsOfDirectory(
                    atPath: directory.path
                )
            } catch {
                return []
            }
        }
    }
    
    /// Get the storage directory URL
    public var directoryURL: URL {
        return directory
    }
}
