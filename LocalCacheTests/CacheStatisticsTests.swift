import XCTest
@testable import LocalCache

final class CacheStatisticsTests: XCTestCase {
    var cache: MemoryCache<String, String>!
    
    override func setUp() async throws {
        cache = MemoryCache(configuration: .memoryCache(maxItems: 10, maxCost: 100))
    }
    
    override func tearDown() async throws {
        cache = nil
    }
    
    // MARK: - Basic Statistics
    
    func testInitialStatistics() async throws {
        let stats = cache.stats
        XCTAssertEqual(stats.hits, 0)
        XCTAssertEqual(stats.misses, 0)
        XCTAssertEqual(stats.writes, 0)
        XCTAssertEqual(stats.hitRate, 0.0)
    }
    
    func testHitRateTracking() async throws {
        // Miss
        _ = try await cache.get(forKey: "nonexistent")
        
        // Hit
        try await cache.set("value1", forKey: "key1")
        _ = try await cache.get(forKey: "key1")
        
        let stats = cache.stats
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.writes, 1)
        XCTAssertEqual(stats.hitRate, 0.5)
        XCTAssertEqual(stats.hitRatePercentage, 50.0)
    }
    
    func testWriteTracking() async throws {
        try await cache.set("value1", forKey: "key1")
        try await cache.set("value2", forKey: "key2")
        try await cache.set("value3", forKey: "key3")
        
        let stats = cache.stats
        XCTAssertEqual(stats.writes, 3)
    }
    
    func testRemoveTracking() async throws {
        try await cache.set("value1", forKey: "key1")
        try await cache.remove(forKey: "key1")
        
        let stats = cache.stats
        XCTAssertEqual(stats.writes, 1)
        XCTAssertEqual(stats.removes, 1)
    }
    
    // MARK: - Eviction Statistics
    
    func testEvictionTracking() async throws {
        let smallCache = MemoryCache<String, String>(
            configuration: .memoryCache(maxItems: 3, maxCost: 100)
        )
        
        // Fill cache
        try await smallCache.set("value1", forKey: "key1")
        try await smallCache.set("value2", forKey: "key2")
        try await smallCache.set("value3", forKey: "key3")
        
        // Add one more, should evict one
        try await smallCache.set("value4", forKey: "key4")
        
        let stats = smallCache.stats
        XCTAssertGreaterThanOrEqual(stats.evictions, 1)
    }
    
    func testEvictionByCostTracking() async throws {
        let smallCache = MemoryCache<String, String>(
            configuration: .memoryCache(maxItems: 100, maxCost: 5)
        )
        
        // Add items until eviction happens
        for i in 0..<10 {
            try await smallCache.set("value\(i)", forKey: "key\(i)")
        }
        
        let stats = smallCache.stats
        XCTAssertGreaterThanOrEqual(stats.evictions, 1)
    }
    
    // MARK: - Cleanup Statistics
    
    func testCleanupExpiredTracking() async throws {
        try await cache.set("value1", forKey: "key1", expiration: 0.1)
        try await cache.set("value2", forKey: "key2", expiration: 0.1)
        
        try await Task.sleep(nanoseconds: 150_000_000)
        try await cache.cleanupExpired()
        
        let stats = cache.stats
        XCTAssertGreaterThanOrEqual(stats.evictions, 2)
    }
    
    // MARK: - Hit Rate Calculations
    
    func testHitRateCalculation() async throws {
        // 3 misses
        _ = try? await cache.get(forKey: "key1")
        _ = try? await cache.get(forKey: "key2")
        _ = try? await cache.get(forKey: "key3")
        
        // 3 hits
        try await cache.set("value4", forKey: "key4")
        try await cache.set("value5", forKey: "key5")
        try await cache.set("value6", forKey: "key6")
        _ = try await cache.get(forKey: "key4")
        _ = try await cache.get(forKey: "key5")
        _ = try await cache.get(forKey: "key6")
        
        let stats = cache.stats
        XCTAssertEqual(stats.hits, 3)
        XCTAssertEqual(stats.misses, 3)
        XCTAssertEqual(stats.hitRate, 0.5)
        XCTAssertEqual(stats.hitRatePercentage, 50.0)
    }
    
    func testHitRateAfterReset() async throws {
        try await cache.set("value1", forKey: "key1")
        _ = try await cache.get(forKey: "key1")
        
        // Verify initial stats
        var stats = cache.stats
        XCTAssertEqual(stats.hits, 1)
        
        // Reset
        cache.statisticsTracker.reset()
        
        stats = cache.stats
        XCTAssertEqual(stats.hits, 0)
        XCTAssertEqual(stats.misses, 0)
        XCTAssertEqual(stats.writes, 0)
    }
    
    // MARK: - Operations Per Second
    
    func testOperationsPerSecond() async throws {
        let startTime = Date()
        
        // Perform some operations
        for i in 0..<10 {
            try await cache.set("value\(i)", forKey: "key\(i)")
        }
        
        let stats = cache.stats
        XCTAssertGreaterThan(stats.uptime, 0)
        XCTAssertGreaterThanOrEqual(stats.totalOperations, 10)
        XCTAssertGreaterThanOrEqual(stats.operationsPerSecond, 0)
    }
    
    // MARK: - Statistics Description
    
    func testStatisticsDescription() async throws {
        try await cache.set("value1", forKey: "key1")
        _ = try await cache.get(forKey: "key1")
        _ = try await cache.get(forKey: "nonexistent")
        
        let stats = cache.stats
        let description = stats.description
        
        XCTAssertTrue(description.contains("Hits:"))
        XCTAssertTrue(description.contains("Misses:"))
        XCTAssertTrue(description.contains("Hit Rate:"))
        XCTAssertTrue(description.contains("Writes:"))
    }
    
    // MARK: - Hybrid Cache Statistics
    
    func testHybridCacheStatistics() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HybridStatsTests-\(UUID().uuidString)")
        
        let config = CacheConfiguration.hybridCache(
            memoryItems: 20,
            diskSize: 10 * 1024 * 1024
        )
        
        let hybridCache = HybridCache<String, String>(configuration: config)
        try await hybridCache.prepare()
        
        // Perform operations
        try await hybridCache.set("value1", forKey: "key1")
        try await hybridCache.set("value2", forKey: "key2")
        _ = try await hybridCache.get(forKey: "key1")
        _ = try await hybridCache.get(forKey: "nonexistent")
        
        // Give async disk writes time
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let stats = try await hybridCache.statistics
        XCTAssertGreaterThanOrEqual(stats.memoryCount, 0)
        XCTAssertGreaterThanOrEqual(stats.diskCount, 0)
        XCTAssertGreaterThanOrEqual(stats.diskSizeBytes, 0)
        
        // Memory stats should be available
        if let memStats = stats.memoryStats {
            XCTAssertGreaterThanOrEqual(memStats.hits, 0)
            XCTAssertGreaterThanOrEqual(memStats.misses, 0)
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Concurrent Statistics Access
    
    func testConcurrentStatisticsAccess() async throws {
        let group = TaskGroup<Void>()
        
        // Concurrent writes and reads
        for i in 0..<50 {
            group.addTask {
                try? await self.cache.set("value\(i)", forKey: "key\(i)")
            }
            
            group.addTask {
                _ = try? await self.cache.get(forKey: "key\(i)")
            }
        }
        
        await group.waitForAll()
        
        // Access statistics concurrently
        let statsGroup = TaskGroup<Void>()
        for _ in 0..<10 {
            statsGroup.addTask {
                _ = self.cache.stats
            }
        }
        
        await statsGroup.waitForAll()
        
        let finalStats = cache.stats
        XCTAssertGreaterThanOrEqual(finalStats.totalOperations, 100)
    }
}

// MARK: - CacheStatsSnapshot Tests

final class CacheStatsSnapshotTests: XCTestCase {
    func testSnapshotProperties() {
        let snapshot = CacheStatsSnapshot(
            hits: 80,
            misses: 20,
            writes: 100,
            removes: 10,
            evictions: 5,
            hitRate: 0.8,
            uptime: 60.0,
            operationsPerSecond: 3.5
        )
        
        XCTAssertEqual(snapshot.totalReads, 100)
        XCTAssertEqual(snapshot.totalOperations, 215)
        XCTAssertEqual(snapshot.hitRatePercentage, 80.0)
    }
    
    func testZeroHitRate() {
        let snapshot = CacheStatsSnapshot(
            hits: 0,
            misses: 10,
            writes: 0,
            removes: 0,
            evictions: 0,
            hitRate: 0.0,
            uptime: 10.0,
            operationsPerSecond: 1.0
        )
        
        XCTAssertEqual(snapshot.hitRate, 0.0)
        XCTAssertEqual(snapshot.hitRatePercentage, 0.0)
    }
    
    func testPerfectHitRate() {
        let snapshot = CacheStatsSnapshot(
            hits: 100,
            misses: 0,
            writes: 50,
            removes: 0,
            evictions: 0,
            hitRate: 1.0,
            uptime: 30.0,
            operationsPerSecond: 5.0
        )
        
        XCTAssertEqual(snapshot.hitRate, 1.0)
        XCTAssertEqual(snapshot.hitRatePercentage, 100.0)
    }
}
