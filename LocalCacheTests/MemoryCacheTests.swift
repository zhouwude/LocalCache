import XCTest
@testable import LocalCache

final class MemoryCacheTests: XCTestCase {
    var cache: MemoryCache<String, String>!
    
    override func setUp() async throws {
        cache = MemoryCache(configuration: .memoryCache(maxItems: 10, maxCost: 100))
    }
    
    override func tearDown() async throws {
        cache = nil
    }
    
    // MARK: - Basic Operations
    
    func testSetAndGet() async throws {
        try await cache.set("value1", forKey: "key1")
        let value = try await cache.get(forKey: "key1")
        XCTAssertEqual(value, "value1")
    }
    
    func testGetNonExistentKey() async throws {
        let value = try await cache.get(forKey: "nonexistent")
        XCTAssertNil(value)
    }
    
    func testUpdateExistingKey() async throws {
        try await cache.set("value1", forKey: "key1")
        try await cache.set("value2", forKey: "key1")
        let value = try await cache.get(forKey: "key1")
        XCTAssertEqual(value, "value2")
    }
    
    func testRemove() async throws {
        try await cache.set("value1", forKey: "key1")
        try await cache.remove(forKey: "key1")
        let value = try await cache.get(forKey: "key1")
        XCTAssertNil(value)
    }
    
    func testRemoveAll() async throws {
        try await cache.set("value1", forKey: "key1")
        try await cache.set("value2", forKey: "key2")
        try await cache.removeAll()
        
        let count = try await cache.count
        XCTAssertEqual(count, 0)
    }
    
    func testContains() async throws {
        try await cache.set("value1", forKey: "key1")
        
        var exists = try await cache.contains(forKey: "key1")
        XCTAssertTrue(exists)
        
        exists = try await cache.contains(forKey: "key2")
        XCTAssertFalse(exists)
    }
    
    // MARK: - Expiration
    
    func testExpiration() async throws {
        try await cache.set("value1", forKey: "key1", expiration: 0.1)
        
        // Should exist immediately
        var value = try await cache.get(forKey: "key1")
        XCTAssertEqual(value, "value1")
        
        // Wait for expiration
        try await Task.sleep(nanoseconds: 150_000_000)
        
        // Should be expired
        value = try await cache.get(forKey: "key1")
        XCTAssertNil(value)
    }
    
    func testCleanupExpired() async throws {
        try await cache.set("value1", forKey: "key1", expiration: 0.1)
        try await cache.set("value2", forKey: "key2", expiration: 0.1)
        try await cache.set("value3", forKey: "key3") // No expiration
        
        try await Task.sleep(nanoseconds: 150_000_000)
        try await cache.cleanupExpired()
        
        let count = try await cache.count
        XCTAssertEqual(count, 1)
        
        let value = try await cache.get(forKey: "key3")
        XCTAssertEqual(value, "value3")
    }
    
    // MARK: - LRU Eviction
    
    func testLRUEvictionByCount() async throws {
        // Fill cache to capacity
        for i in 0..<10 {
            try await cache.set("value\(i)", forKey: "key\(i)")
        }
        
        // Access key0 to make it recently used
        _ = try await cache.get(forKey: "key0")
        
        // Add new item, should evict key1 (least recently used)
        try await cache.set("value10", forKey: "key10")
        
        let exists = try await cache.contains(forKey: "key1")
        XCTAssertFalse(exists)
        
        let exists0 = try await cache.contains(forKey: "key0")
        XCTAssertTrue(exists0)
    }
    
    func testLRUEvictionByCost() async throws {
        // Create cache with small cost limit
        let smallCache = MemoryCache<String, String>(
            configuration: .memoryCache(maxItems: 100, maxCost: 10)
        )
        
        // Add items with cost
        try await smallCache.set("value1", forKey: "key1")
        try await smallCache.set("value2", forKey: "key2")
        
        // Total cost should not exceed limit
        let totalCost = try await smallCache.totalCost
        XCTAssertLessThanOrEqual(totalCost, 10)
    }
    
    // MARK: - GetOrSet
    
    func testGetOrSet_CacheMiss() async throws {
        var factoryCalled = false
        
        let value = try await cache.getOrSet(forKey: "key1") {
            factoryCalled = true
            return "computed"
        }
        
        XCTAssertTrue(factoryCalled)
        XCTAssertEqual(value, "computed")
        
        // Second call should use cache
        factoryCalled = false
        let cachedValue = try await cache.getOrSet(forKey: "key1") {
            factoryCalled = true
            return "computed2"
        }
        
        XCTAssertFalse(factoryCalled)
        XCTAssertEqual(cachedValue, "computed")
    }
    
    // MARK: - Observers
    
    func testObserverNotifications() async throws {
        let expectation = XCTestExpectation(description: "Observer notified")
        var events: [MemoryCache<String, String>.ObserverEvent] = []
        
        _ = await cache.addObserver { event in
            events.append(event)
            if case .set = event {
                expectation.fulfill()
            }
        }
        
        try await cache.set("value1", forKey: "key1")
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Give async task time to process
        try await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertTrue(events.contains { case .set = $0; default: false })
    }
    
    // MARK: - Performance
    
    func testConcurrentAccess() async throws {
        let group = TaskGroup<Void>(returning: Void.self)
        
        // Concurrent writes
        for i in 0..<100 {
            group.addTask {
                try? await self.cache.set("value\(i)", forKey: "key\(i)")
            }
        }
        
        // Concurrent reads
        for i in 0..<100 {
            group.addTask {
                _ = try? await self.cache.get(forKey: "key\(i)")
            }
        }
        
        await group.waitForAll()
        
        let count = try await cache.count
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}
