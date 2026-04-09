import Foundation

/// Thread-safe cache statistics tracker
public final class CacheStatisticsTracker {
    private let lock: Lock
    private var hits: Int = 0
    private var misses: Int = 0
    private var writes: Int = 0
    private var removes: Int = 0
    private var evictions: Int = 0
    private var startTime: Date
    
    /// Initialize statistics tracker
    public init() {
        self.lock = Lock()
        self.startTime = Date()
    }
    
    /// Record a cache hit
    public func recordHit() {
        lock.sync { hits += 1 }
    }
    
    /// Record a cache miss
    public func recordMiss() {
        lock.sync { misses += 1 }
    }
    
    /// Record a cache write
    public func recordWrite() {
        lock.sync { writes += 1 }
    }
    
    /// Record a cache removal
    public func recordRemove() {
        lock.sync { removes += 1 }
    }
    
    /// Record an eviction
    public func recordEviction() {
        lock.sync { evictions += 1 }
    }
    
    /// Record multiple evictions
    public func recordEvictions(_ count: Int) {
        lock.sync { evictions += count }
    }
    
    /// Get current statistics snapshot
    public var snapshot: CacheStatsSnapshot {
        lock.sync {
            let total = hits + misses
            let hitRate = total > 0 ? Double(hits) / Double(total) : 0.0
            let uptime = Date().timeIntervalSince(startTime)
            
            return CacheStatsSnapshot(
                hits: hits,
                misses: misses,
                writes: writes,
                removes: removes,
                evictions: evictions,
                hitRate: hitRate,
                uptime: uptime,
                operationsPerSecond: Double(total) / max(uptime, 1.0)
            )
        }
    }
    
    /// Reset all statistics
    public func reset() {
        lock.sync {
            hits = 0
            misses = 0
            writes = 0
            removes = 0
            evictions = 0
            startTime = Date()
        }
    }
}

/// Snapshot of cache statistics at a point in time
public struct CacheStatsSnapshot {
    public let hits: Int
    public let misses: Int
    public let writes: Int
    public let removes: Int
    public let evictions: Int
    public let hitRate: Double
    public let uptime: TimeInterval
    public let operationsPerSecond: Double
    
    public var totalReads: Int { hits + misses }
    public var totalOperations: Int { hits + misses + writes + removes }
    public var hitRatePercentage: Double { hitRate * 100.0 }
}

// MARK: - CustomStringConvertible

extension CacheStatsSnapshot: CustomStringConvertible {
    public var description: String {
        return """
        Cache Statistics:
          - Hits: \(hits)
          - Misses: \(misses)
          - Hit Rate: \(String(format: "%.2f", hitRatePercentage))%
          - Writes: \(writes)
          - Removes: \(removes)
          - Evictions: \(evictions)
          - Total Operations: \(totalOperations)
          - Ops/sec: \(String(format: "%.2f", operationsPerSecond))
          - Uptime: \(String(format: "%.1f", uptime))s
        """
    }
}
