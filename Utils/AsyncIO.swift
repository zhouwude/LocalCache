import Foundation

/// Async I/O utilities for file operations
public enum AsyncIO {
    private static let ioQueue = DispatchQueue(
        label: "com.localcache.asyncio",
        qos: .utility,
        attributes: .concurrent
    )
    
    /// Read data from a file asynchronously
    /// - Parameter url: File URL
    /// - Returns: The data
    /// - Throws: CacheError.diskIOError if read fails
    public static func read(from url: URL) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: CacheError.diskIOError(error.localizedDescription))
                }
            }
        }
    }
    
    /// Write data to a file asynchronously
    /// - Parameters:
    ///   - url: File URL
    ///   - data: Data to write
    /// - Throws: CacheError.diskIOError if write fails
    public static func write(to url: URL, data: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    try data.write(to: url, options: .atomic)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: CacheError.diskIOError(error.localizedDescription))
                }
            }
        }
    }
    
    /// Read a file as string asynchronously
    /// - Parameters:
    ///   - url: File URL
    ///   - encoding: String encoding (default: UTF-8)
    /// - Returns: The string content
    /// - Throws: CacheError.diskIOError if read fails
    public static func readString(
        from url: URL,
        encoding: String.Encoding = .utf8
    ) async throws -> String {
        let data = try await read(from: url)
        guard let string = String(data: data, encoding: encoding) else {
            throw CacheError.diskIOError("Failed to decode string from file")
        }
        return string
    }
    
    /// Write a string to a file asynchronously
    /// - Parameters:
    ///   - url: File URL
    ///   - string: String to write
    ///   - encoding: String encoding (default: UTF-8)
    /// - Throws: CacheError.diskIOError if write fails
    public static func writeString(
        to url: URL,
        string: String,
        encoding: String.Encoding = .utf8
    ) async throws {
        guard let data = string.data(using: encoding) else {
            throw CacheError.diskIOError("Failed to encode string to data")
        }
        try await write(to: url, data: data)
    }
    
    /// Check if a file exists
    /// - Parameter url: File URL
    /// - Returns: true if exists
    public static func exists(at url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            ioQueue.async {
                let exists = FileManager.default.fileExists(atPath: url.path)
                continuation.resume(returning: exists)
            }
        }
    }
    
    /// Get file attributes
    /// - Parameter url: File URL
    /// - Returns: File attributes
    /// - Throws: CacheError.diskIOError if failed
    public static func attributes(of url: URL) async throws -> [FileAttributeKey: Any] {
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    continuation.resume(returning: attributes)
                } catch {
                    continuation.resume(throwing: CacheError.diskIOError(error.localizedDescription))
                }
            }
        }
    }
    
    /// Get file size
    /// - Parameter url: File URL
    /// - Returns: File size in bytes, or nil if doesn't exist
    public static func fileSize(at url: URL) async -> Int64? {
        guard let attributes = try? await attributes(of: url) else {
            return nil
        }
        return attributes[.size] as? Int64
    }
    
    /// Remove a file
    /// - Parameter url: File URL
    /// - Throws: CacheError.diskIOError if failed
    public static func remove(at url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    try FileManager.default.removeItem(at: url)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: CacheError.diskIOError(error.localizedDescription))
                }
            }
        }
    }
    
    /// Move a file
    /// - Parameters:
    ///   - source: Source URL
    ///   - destination: Destination URL
    /// - Throws: CacheError.diskIOError if failed
    public static func move(from source: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    try FileManager.default.moveItem(at: source, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: CacheError.diskIOError(error.localizedDescription))
                }
            }
        }
    }
    
    /// Copy a file
    /// - Parameters:
    ///   - source: Source URL
    ///   - destination: Destination URL
    /// - Throws: CacheError.diskIOError if failed
    public static func copy(from source: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: CacheError.diskIOError(error.localizedDescription))
                }
            }
        }
    }
}

/// Async stream for large file operations
public final class AsyncFileStream: AsyncSequence {
    public typealias Element = Data
    
    private let url: URL
    private let chunkSize: Int
    
    public init(url: URL, chunkSize: Int = 4096) {
        self.url = url
        self.chunkSize = chunkSize
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol, @unchecked Sendable {
        private var handle: FileHandle?
        private let chunkSize: Int
        private var isEOF: Bool = false
        
        init?(url: URL, chunkSize: Int) {
            self.chunkSize = chunkSize
            self.handle = try? FileHandle(forReadingFrom: url)
            
            if handle == nil {
                return nil
            }
        }
        
        public mutating func next() async -> Data? {
            guard let handle = handle, !isEOF else { return nil }
            
            return await withCheckedContinuation { continuation in
                let data = handle.readData(ofLength: chunkSize)
                if data.isEmpty {
                    self.isEOF = true
                    try? handle.close()
                    self.handle = nil
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }
    
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(url: url, chunkSize: chunkSize)!
    }
}
