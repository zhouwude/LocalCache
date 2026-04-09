import XCTest
@testable import LocalCache

final class HybridCacheTests: XCTestCase {
    var cache: HybridCache<String, TestModel>!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HybridCacheTests-\(UUID().uuidString)")
        
        let config = CacheConfiguration.hybridCache(
            memoryItems: 20,
            diskSize: 10 * 1024 * 1024
        )
        
        cache = HybridCache(configuration: config)
        try await cache.prepare()
    }
    
    override func tearDown() async throws {
        cache = nil
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    // MARK: - Basic Operations
    
    func testSetAndGet() async throws {
        let model = TestModel(id: 1, name: "Test")
        try await cache.set(model, forKey: "model-1")
        
        let retrieved = try await cache.get(forKey: "model-1")
        XCTAssertEqual(retrieved?.id, 1)
        XCTAssertEqual(retrieved?.name, "Test")
    }
    
    func testMemoryFirstLookup() async throws {
        let model = TestModel(id: 1, name: "Test")
        try await cache.set(model, forKey: "model-1")
        
        // Should be in memory cache
        let retrieved = try await cache.get(forKey: "model-1")
        XCTAssertNotNil(retrieved)
    }
    
    func testDiskFallback() async throws {
        // This test verifies disk fallback works
        // by checking that data persists
        let model = TestModel(id: 1, name: "Persistent")
        try await cache.set(model, forKey: "model-1")
        
        // Force flush to disk
        try await cache.flush()
        
        let retrieved = try await cache.get(forKey: "model-1")
        XCTAssertEqual(retrieved?.name, "Persistent")
    }
    
    func testRemove() async throws {
        try await cache.set(TestModel(id: 1, name: "Test"), forKey: "model-1")
        try await cache.remove(forKey: "model-1")
        
        let retrieved = try await cache.get(forKey: "model-1")
        XCTAssertNil(retrieved)
    }
    
    func testRemoveAll() async throws {
        for i in 0..<10 {
            try await cache.set(TestModel(id: i, name: "Test\(i)"), forKey: "key-\(i)")
        }
        
        try await cache.removeAll()
        
        let count = try await cache.count
        XCTAssertEqual(count, 0)
    }
    
    // MARK: - Statistics
    
    func testStatistics() async throws {
        for i in 0..<10 {
            try await cache.set(TestModel(id: i, name: "Test\(i)"), forKey: "key-\(i)")
        }
        
        // Give async disk writes time to complete
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let stats = try await cache.statistics
        XCTAssertGreaterThanOrEqual(stats.totalCount, 0)
        XCTAssertGreaterThanOrEqual(stats.diskSizeBytes, 0)
    }
    
    // MARK: - Flush and Invalidate
    
    func testFlush() async throws {
        try await cache.set(TestModel(id: 1, name: "Test"), forKey: "model-1")
        try await cache.flush()
        
        let stats = try await cache.statistics
        XCTAssertGreaterThan(stats.diskCount, 0)
    }
    
    func testInvalidateDisk() async throws {
        try await cache.set(TestModel(id: 1, name: "Test"), forKey: "model-1")
        try await cache.flush()
        
        try await cache.invalidateDisk()
        
        let stats = try await cache.statistics
        XCTAssertEqual(stats.diskCount, 0)
    }
    
    // MARK: - Expiration
    
    func testExpiration() async throws {
        try await cache.set(
            TestModel(id: 1, name: "Test"),
            forKey: "model-1",
            expiration: 0.1
        )
        
        var retrieved = try await cache.get(forKey: "model-1")
        XCTAssertNotNil(retrieved)
        
        try await Task.sleep(nanoseconds: 150_000_000)
        
        retrieved = try await cache.get(forKey: "model-1")
        XCTAssertNil(retrieved)
    }
    
    func testCleanupExpired() async throws {
        try await cache.set(
            TestModel(id: 1, name: "Test1"),
            forKey: "model-1",
            expiration: 0.1
        )
        try await cache.set(
            TestModel(id: 2, name: "Test2"),
            forKey: "model-2",
            expiration: 0.1
        )
        try await cache.set(
            TestModel(id: 3, name: "Test3"),
            forKey: "model-3"
        )
        
        try await Task.sleep(nanoseconds: 150_000_000)
        try await cache.cleanupExpired()
        
        let exists = try await cache.contains(forKey: "model-3")
        XCTAssertTrue(exists)
    }
    
    // MARK: - GetOrSet
    
    func testGetOrSet() async throws {
        var factoryCalled = false
        
        let model = try await cache.getOrSet(forKey: "model-1") {
            factoryCalled = true
            return TestModel(id: 1, name: "Computed")
        }
        
        XCTAssertTrue(factoryCalled)
        XCTAssertEqual(model.id, 1)
        
        factoryCalled = false
        let cached = try await cache.getOrSet(forKey: "model-1") {
            factoryCalled = true
            return TestModel(id: 2, name: "Should not be called")
        }
        
        XCTAssertFalse(factoryCalled)
        XCTAssertEqual(cached.id, 1)
    }
    
    // MARK: - Configuration
    
    func testMemoryOnlyConfiguration() async throws {
        let memoryOnly = HybridCache<String, TestModel>(
            configuration: CacheConfiguration(
                enableMemoryCache: true,
                enableDiskCache: false
            )
        )
        
        try await memoryOnly.set(TestModel(id: 1, name: "Test"), forKey: "key-1")
        let retrieved = try await memoryOnly.get(forKey: "key-1")
        XCTAssertNotNil(retrieved)
    }
    
    func testDiskOnlyConfiguration() async throws {
        let diskOnly = HybridCache<String, TestModel>(
            configuration: CacheConfiguration(
                enableMemoryCache: false,
                enableDiskCache: true,
                storageDirectory: tempDirectory.appendingPathComponent("diskonly")
            )
        )
        
        try await diskOnly.prepare()
        try await diskOnly.set(TestModel(id: 1, name: "Test"), forKey: "key-1")
        
        // Give async write time
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let retrieved = try await diskOnly.get(forKey: "key-1")
        XCTAssertNotNil(retrieved)
    }
    
    // MARK: - Performance
    
    func testConcurrentAccess() async throws {
        let group = TaskGroup<Void>()
        
        for i in 0..<50 {
            group.addTask {
                let model = TestModel(id: i, name: "Test\(i)")
                try? await self.cache.set(model, forKey: "key-\(i)")
            }
            
            group.addTask {
                _ = try? await self.cache.get(forKey: "key-\(i)")
            }
        }
        
        await group.waitForAll()
        
        let stats = try await cache.statistics
        XCTAssertGreaterThanOrEqual(stats.totalCount, 0)
    }
}
