import Foundation

/// Manages cache entry expiration and cleanup
public final class ExpirationManager {
    private let lock: Lock
    private var cleanupTasks: [String: Task<Void, Never>] = [:]

    /// Shared instance for global expiration management
    public static let shared = ExpirationManager()

    private init() {
        self.lock = Lock()
    }

    /// Schedule a cleanup task
    /// - Parameters:
    ///   - cacheId: Unique cache identifier
    ///   - interval: Cleanup interval in seconds
    ///   - cleanup: The cleanup closure to execute
    public func schedule(
        cacheId: String,
        interval: TimeInterval = 300, // 5 minutes default
        cleanup: @escaping () async -> Void
    ) {
        lock.sync {
            // Cancel existing task
            cleanupTasks[cacheId]?.cancel()

            // Create new async task for cleanup
            let task = Task {
                // Execute cleanup immediately on first run
                await cleanup()

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                    if Task.isCancelled { break }

                    await cleanup()
                }
            }

            cleanupTasks[cacheId] = task
        }
    }

    /// Cancel a scheduled cleanup task
    /// - Parameter cacheId: Cache identifier
    public func cancel(cacheId: String) {
        lock.sync {
            cleanupTasks[cacheId]?.cancel()
            cleanupTasks.removeValue(forKey: cacheId)
        }
    }

    /// Cancel all scheduled tasks
    public func cancelAll() {
        lock.sync {
            for task in cleanupTasks.values {
                task.cancel()
            }
            cleanupTasks.removeAll()
        }
    }
    
    /// Get next expiration time for a set of entries
    /// - Parameter entries: Dictionary of entries
    /// - Returns: The earliest expiration date, or nil if no entries expire
    public func nextExpiration<Value>(for entries: [String: CacheEntry<Value>]) -> Date? {
        return entries.compactMap { $0.value.expiresAt }
            .filter { $0 > Date() }
            .min()
    }
    
    /// Get entries that will expire within a time window
    /// - Parameters:
    ///   - entries: Dictionary of entries
    ///   - window: Time window in seconds
    /// - Returns: Array of keys that will expire soon
    public func expiringSoon<Value>(
        in entries: [String: CacheEntry<Value>],
        within window: TimeInterval = 60
    ) -> [String] {
        let soon = Date().addingTimeInterval(window)
        return entries.compactMap { key, entry in
            guard let expiresAt = entry.expiresAt,
                  expiresAt > Date(),
                  expiresAt <= soon else {
                return nil
            }
            return key
        }
    }
    
    /// Calculate optimal cleanup interval based on expiration patterns
    /// - Parameter entries: Dictionary of entries
    /// - Returns: Suggested cleanup interval in seconds
    public func optimalCleanupInterval<Value>(
        for entries: [String: CacheEntry<Value>]
    ) -> TimeInterval {
        guard !entries.isEmpty else { return 300 }
        
        let expirations = entries.compactMap { $0.value.expiresAt }
            .filter { $0 > Date() }
        
        guard !expirations.isEmpty else { return 3600 } // No expirations, cleanup hourly
        
        // Find the median time to expiration
        let now = Date()
        let timesToExpire = expirations.map { $0.timeIntervalSince(now) }
            .sorted()
        
        let medianIndex = timesToExpire.count / 2
        let medianTime = timesToExpire[medianIndex]
        
        // Cleanup at 1/10th of median expiration time, min 30s, max 600s
        return min(600, max(30, medianTime / 10))
    }
}

/// Expiration policy
public enum ExpirationPolicy {
    /// Never expire
    case never
    
    /// Expire after a fixed time interval
    case after(TimeInterval)
    
    /// Expire at a specific date
    case at(Date)
    
    /// Expire based on access time (time since last access)
    case accessBased(TimeInterval)
    
    /// Get expiration date from policy
    /// - Parameter createdAt: When the entry was created
    /// - Returns: Expiration date, or nil if never
    public func expirationDate(createdAt: Date = Date(), lastAccessed: Date = Date()) -> Date? {
        switch self {
        case .never:
            return nil
        case .after(let interval):
            return createdAt.addingTimeInterval(interval)
        case .at(let date):
            return date
        case .accessBased(let interval):
            return lastAccessed.addingTimeInterval(interval)
        }
    }
}
