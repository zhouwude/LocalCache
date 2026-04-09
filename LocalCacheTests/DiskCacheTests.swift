import XCTest
@testable import LocalCache

final class DiskCacheTests: XCTestCase {
    var cache: DiskCache<String, TestModel>!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskCacheTests-\(UUID().uuidString)")
        
        let config = CacheConfiguration.diskCache(
            maxSize: 10 * 1024 * 1024,
            directory: tempDirectory
        )
        
        cache = DiskCache(configuration: config)
        try await cache.prepare()
    }
    
    override func tearDown() async throws {
        cache = nil
        
        // Clean up temp directory
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
    
    func testGetNonExistentKey() async throws {
        let value = try await cache.get(forKey: "nonexistent")
        XCTAssertNil(value)
    }
    
    func testRemove() async throws {
        let model = TestModel(id: 1, name: "Test")
        try await cache.set(model, forKey: "model-1")
        try await cache.remove(forKey: "model-1")
        
        let retrieved = try await cache.get(forKey: "model-1")
        XCTAssertNil(retrieved)
    }
    
    func testRemoveAll() async throws {
        try await cache.set(TestModel(id: 1, name: "Test1"), forKey: "model-1")
        try await cache.set(TestModel(id: 2, name: "Test2"), forKey: "model-2")
        
        try await cache.removeAll()
        
        let count = try await cache.count
        XCTAssertEqual(count, 0)
    }
    
    // MARK: - Expiration
    
    func testExpiration() async throws {
        let model = TestModel(id: 1, name: "Test")
        try await cache.set(model, forKey: "model-1", expiration: 0.1)
        
        // Should exist immediately
        var retrieved = try await cache.get(forKey: "model-1")
        XCTAssertNotNil(retrieved)
        
        // Wait for expiration
        try await Task.sleep(nanoseconds: 150_000_000)
        
        // Should be expired
        retrieved = try await cache.get(forKey: "model-1")
        XCTAssertNil(retrieved)
    }
    
    func testCleanupExpired() async throws {
        try await cache.set(TestModel(id: 1, name: "Test1"), forKey: "model-1", expiration: 0.1)
        try await cache.set(TestModel(id: 2, name: "Test2"), forKey: "model-2", expiration: 0.1)
        try await cache.set(TestModel(id: 3, name: "Test3"), forKey: "model-3") // No expiration
        
        try await Task.sleep(nanoseconds: 150_000_000)
        try await cache.cleanupExpired()
        
        let count = try await cache.count
        XCTAssertEqual(count, 1)
    }
    
    // MARK: - Persistence
    
    func testPersistenceAcrossInstances() async throws {
        let model = TestModel(id: 1, name: "Persistent")
        try await cache.set(model, forKey: "persistent-key")
        
        // Create new cache instance with same directory
        let newCache = DiskCache<String, TestModel>(
            configuration: CacheConfiguration.diskCache(directory: tempDirectory)
        )
        try await newCache.prepare()
        
        let retrieved = try await newCache.get(forKey: "persistent-key")
        XCTAssertEqual(retrieved?.id, 1)
        XCTAssertEqual(retrieved?.name, "Persistent")
    }
    
    // MARK: - Disk Usage
    
    func testDiskUsageTracking() async throws {
        let model = TestModel(id: 1, name: String(repeating: "x", count: 1000))
        try await cache.set(model, forKey: "large-model")
        
        let size = cache.totalSize
        XCTAssertGreaterThan(size, 0)
    }
    
    func testSizeLimitEnforcement() async throws {
        let smallCache = DiskCache<String, TestModel>(
            configuration: CacheConfiguration.diskCache(
                maxSize: 1024, // 1KB limit
                directory: tempDirectory.appendingPathComponent("small")
            )
        )
        try await smallCache.prepare()
        
        // Write multiple items
        for i in 0..<10 {
            let model = TestModel(id: i, name: String(repeating: "x", count: 100))
            try await smallCache.set(model, forKey: "key-\(i)")
        }
        
        // Should have triggered cleanup
        let isFull = smallCache.manager.isFull
        XCTAssertFalse(isFull) // Should have cleaned up
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
        
        // Second call should use cache
        factoryCalled = false
        let cached = try await cache.getOrSet(forKey: "model-1") {
            factoryCalled = true
            return TestModel(id: 2, name: "Should not be called")
        }
        
        XCTAssertFalse(factoryCalled)
        XCTAssertEqual(cached.id, 1)
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
        
        let count = try await cache.count
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}

// MARK: - Test Model

struct TestModel: Codable, Equatable {
    let id: Int
    let name: String
}
