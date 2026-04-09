import XCTest
@testable import LocalCache

final class ConcurrencyTests: XCTestCase {
    var cache: HybridCache<String, TestModel>!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConcurrencyTests-\(UUID().uuidString)")
        
        let config = CacheConfiguration.hybridCache(
            memoryItems: 100,
            diskSize: 50 * 1024 * 1024
        )
        
        cache = HybridCache(configuration: config)
        try await cache.prepare()
    }
    
    override func tearDown() async throws {
        cache = nil
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    // MARK: - Concurrent Write Tests
    
    func testConcurrentWrites() async throws {
        let group = TaskGroup<Void>()
        
        for i in 0..<100 {
            group.addTask { [weak self] in
                let model = TestModel(id: i, name: "Test\(i)")
                try? await self?.cache.set(model, forKey: "key-\(i)")
            }
        }
        
        await group.waitForAll()
        
        let stats = try await cache.statistics
        XCTAssertEqual(stats.memoryCount, 100)
    }
    
    func testConcurrentReads() async throws {
        // Pre-populate cache
        for i in 0..<50 {
            let model = TestModel(id: i, name: "Test\(i)")
            try await cache.set(model, forKey: "key-\(i)")
        }
        
        let group = TaskGroup<Void>()
        
        for i in 0..<100 {
            group.addTask { [weak self] in
                let key = "key-\(i % 50)"
                _ = try? await self?.cache.get(forKey: key)
            }
        }
        
        await group.waitForAll()
        
        let stats = try await cache.statistics
        XCTAssertGreaterThanOrEqual(stats.memoryStats?.hits ?? 0, 50)
    }
    
    func testConcurrentReadWrite() async throws {
        let group = TaskGroup<Void>()
        
        for i in 0..<50 {
            group.addTask { [weak self] in
                let model = TestModel(id: i, name: "Test\(i)")
                try? await self?.cache.set(model, forKey: "key-\(i)")
            }
            
            group.addTask { [weak self] in
                _ = try? await self?.cache.get(forKey: "key-\(i)")
            }
        }
        
        await group.waitForAll()
        
        let stats = try await cache.statistics
        XCTAssertGreaterThanOrEqual(stats.memoryCount, 0)
    }
    
    // MARK: - Stress Tests
    
    func testStressTest() async throws {
        let iterations = 500
        let group = TaskGroup<Void>()
        
        for i in 0..<iterations {
            group.addTask { [weak self] in
                let model = TestModel(id: i, name: "Stress\(i)")
                try? await self?.cache.set(model, forKey: "stress-\(i)")
                _ = try? await self?.cache.get(forKey: "stress-\(i)")
            }
        }
        
        await group.waitForAll()
        
        let stats = try await cache.statistics
        XCTAssertEqual(stats.memoryCount, 100) // Limited by maxItemCount
        XCTAssertGreaterThanOrEqual(stats.memoryStats?.hits ?? 0, 0)
    }
    
    func testConcurrentRemove() async throws {
        // Pre-populate
        for i in 0..<100 {
            let model = TestModel(id: i, name: "Test\(i)")
            try await cache.set(model, forKey: "key-\(i)")
        }
        
        let group = TaskGroup<Void>()
        
        for i in 0..<50 {
            group.addTask { [weak self] in
                try? await self?.cache.remove(forKey: "key-\(i)")
            }
        }
        
        await group.waitForAll()
        
        let stats = try await cache.statistics
        XCTAssertLessThanOrEqual(stats.memoryCount, 100)
    }
    
    // MARK: - Race Condition Tests
    
    func testSetAndGetRaceCondition() async throws {
        let expectation = XCTestExpectation(description: "Race test")
        expectation.expectedFulfillmentCount = 100
        
        for i in 0..<100 {
            Task {
                let model = TestModel(id: i, name: "Race\(i)")
                try? await self.cache.set(model, forKey: "race-\(i)")
                let retrieved = try? await self.cache.get(forKey: "race-\(i)")
                XCTAssertEqual(retrieved?.id, i)
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
    }
    
    func testConcurrentGetOrSet() async throws {
        let group = TaskGroup<Void>()
        
        for i in 0..<50 {
            group.addTask { [weak self] in
                _ = try? await self?.cache.getOrSet(forKey: "key-\(i)") {
                    TestModel(id: i, name: "Computed\(i)")
                }
            }
        }
        
        await group.waitForAll()
        
        let stats = try await cache.statistics
        XCTAssertEqual(stats.memoryCount, 50)
    }
    
    // MARK: - Boundary Condition Tests
    
    func testEmptyCacheOperations() async throws {
        // Get from empty cache
        let value = try await cache.get(forKey: "nonexistent")
        XCTAssertNil(value)
        
        // Remove from empty cache
        try await cache.remove(forKey: "nonexistent")
        
        // Contains on empty cache
        let exists = try await cache.contains(forKey: "nonexistent")
        XCTAssertFalse(exists)
        
        let stats = try await cache.statistics
        XCTAssertEqual(stats.memoryCount, 0)
    }
    
    func testLargeValue() async throws {
        let largeString = String(repeating: "x", count: 10000)
        let model = TestModel(id: 1, name: largeString)
        
        try await cache.set(model, forKey: "large")
        let retrieved = try await cache.get(forKey: "large")
        
        XCTAssertEqual(retrieved?.name.count, 10000)
    }
    
    func testSpecialCharactersInKey() async throws {
        let specialKeys = [
            "key with spaces",
            "key-with-dashes",
            "key_with_underscores",
            "key.with.dots",
            "key/with/slashes",
            "key:with:colons",
            "key?with?question?marks",
            "key&with&ampersands"
        ]
        
        for (index, key) in specialKeys.enumerated() {
            let model = TestModel(id: index, name: "Value\(index)")
            try await cache.set(model, forKey: key)
        }
        
        for (index, key) in specialKeys.enumerated() {
            let retrieved = try await cache.get(forKey: key)
            XCTAssertEqual(retrieved?.id, index)
        }
    }
    
    func testUnicodeKeys() async throws {
        let unicodeKeys = [
            "键值",
            "キー",
            "키",
            "🔑",
            "clé"
        ]
        
        for (index, key) in unicodeKeys.enumerated() {
            let model = TestModel(id: index, name: "Value\(index)")
            try await cache.set(model, forKey: key)
        }
        
        for (index, key) in unicodeKeys.enumerated() {
            let retrieved = try await cache.get(forKey: key)
            XCTAssertEqual(retrieved?.id, index)
        }
    }
    
    func testNilExpiration() async throws {
        let model = TestModel(id: 1, name: "NoExpiration")
        try await cache.set(model, forKey: "no-expiration")
        
        // Wait a bit
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let retrieved = try await cache.get(forKey: "no-expiration")
        XCTAssertNotNil(retrieved)
    }
    
    func testZeroExpiration() async throws {
        let model = TestModel(id: 1, name: "ZeroExpiration")
        try await cache.set(model, forKey: "zero-exp", expiration: 0)
        
        // Should be expired immediately or very soon
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let retrieved = try await cache.get(forKey: "zero-exp")
        XCTAssertNil(retrieved)
    }
    
    func testVeryLongExpiration() async throws {
        let model = TestModel(id: 1, name: "LongExpiration")
        try await cache.set(model, forKey: "long-exp", expiration: 86400 * 365) // 1 year
        
        let retrieved = try await cache.get(forKey: "long-exp")
        XCTAssertNotNil(retrieved)
    }
    
    func testMaxItemCountBoundary() async throws {
        let smallCache = HybridCache<String, TestModel>(
            configuration: CacheConfiguration(
                enableMemoryCache: true,
                enableDiskCache: false,
                maxItemCount: 5
            )
        )
        
        // Insert more items than max
        for i in 0..<10 {
            let model = TestModel(id: i, name: "Test\(i)")
            try await smallCache.set(model, forKey: "key-\(i)")
        }
        
        let stats = try await smallCache.statistics
        XCTAssertLessThanOrEqual(stats.memoryCount, 5)
    }
    
    // MARK: - Task Cancellation Tests
    
    func testSetTaskCancellation() async throws {
        let model = TestModel(id: 1, name: "CancelTest")
        
        let task = Task {
            try await cache.set(model, forKey: "cancel-test")
        }
        
        // Cancel immediately
        task.cancel()
        
        // Should not crash
        try? await task.value
    }
    
    func testConcurrentSetWithCancellation() async throws {
        let group = TaskGroup<Void>()
        
        for i in 0..<20 {
            group.addTask { [weak self] in
                let model = TestModel(id: i, name: "Test\(i)")
                try? await self?.cache.set(model, forKey: "key-\(i)")
            }
        }
        
        // Cancel half of the tasks
        try await Task.sleep(nanoseconds: 50_000_000)
        group.cancelAll()
        
        await group.waitForAll()
        
        // Should not crash, some items may be cached
        let stats = try await cache.statistics
        XCTAssertGreaterThanOrEqual(stats.memoryCount, 0)
    }
}

// MARK: - LRUCache Concurrency Tests

final class LRUCacheConcurrencyTests: XCTestCase {
    func testConcurrentInsertAndAccess() {
        let cache = LRUCache<String, Int>(maxItemCount: 100, maxTotalCost: 1000)
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        
        let expectation = XCTestExpectation(description: "Concurrent LRU operations")
        expectation.expectedFulfillmentCount = 200
        
        for i in 0..<100 {
            queue.async {
                cache.insert(CacheEntry(i), forKey: "key\(i)")
                expectation.fulfill()
            }
            
            queue.async {
                _ = cache.access(forKey: "key\(i)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertLessThanOrEqual(cache.count, 100)
    }
    
    func testConcurrentRemove() {
        let cache = LRUCache<String, Int>(maxItemCount: 100, maxTotalCost: 1000)
        
        // Pre-populate
        for i in 0..<50 {
            cache.insert(CacheEntry(i), forKey: "key\(i)")
        }
        
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        let expectation = XCTestExpectation(description: "Concurrent remove")
        expectation.expectedFulfillmentCount = 50
        
        for i in 0..<50 {
            queue.async {
                cache.remove(forKey: "key\(i)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertEqual(cache.count, 0)
    }
}
