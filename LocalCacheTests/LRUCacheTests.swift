import XCTest
@testable import LocalCache

final class LRUCacheTests: XCTestCase {
    var cache: LRUCache<String, String>!
    
    override func setUp() {
        cache = LRUCache(maxItemCount: 5, maxTotalCost: 100)
    }
    
    override func tearDown() {
        cache = nil
    }
    
    // MARK: - Basic Operations
    
    func testInsertAndAccess() {
        let entry = CacheEntry("value1")
        cache.insert(entry, forKey: "key1")
        
        let accessed = cache.access(forKey: "key1")
        XCTAssertEqual(accessed?.value, "value1")
    }
    
    func testAccessNonExistentKey() {
        let accessed = cache.access(forKey: "nonexistent")
        XCTAssertNil(accessed)
    }
    
    func testRemove() {
        let entry = CacheEntry("value1")
        cache.insert(entry, forKey: "key1")
        
        let removed = cache.remove(forKey: "key1")
        XCTAssertNotNil(removed)
        
        let accessed = cache.access(forKey: "key1")
        XCTAssertNil(accessed)
    }
    
    func testRemoveAll() {
        for i in 0..<5 {
            cache.insert(CacheEntry("value\(i)"), forKey: "key\(i)")
        }
        
        cache.removeAll()
        
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.totalCost, 0)
    }
    
    func testContains() {
        cache.insert(CacheEntry("value1"), forKey: "key1")
        
        XCTAssertTrue(cache.contains(forKey: "key1"))
        XCTAssertFalse(cache.contains(forKey: "key2"))
    }
    
    // MARK: - LRU Order
    
    func testLRUOrder() {
        // Insert items in order
        for i in 0..<5 {
            cache.insert(CacheEntry("value\(i)"), forKey: "key\(i)")
        }
        
        // Access key0 to make it most recently used
        _ = cache.access(forKey: "key0")
        
        // Insert new item, should evict key1 (least recently used)
        cache.insert(CacheEntry("value5"), forKey: "key5")
        
        XCTAssertNil(cache.access(forKey: "key1"))
        XCTAssertNotNil(cache.access(forKey: "key0"))
    }
    
    func testAccessUpdatesOrder() {
        cache.insert(CacheEntry("value1"), forKey: "key1")
        cache.insert(CacheEntry("value2"), forKey: "key2")
        
        // Access key1 to make it most recently used
        _ = cache.access(forKey: "key1")
        
        // Insert new item, should evict key2 (now least recently used)
        cache.insert(CacheEntry("value3"), forKey: "key3")
        
        XCTAssertNotNil(cache.access(forKey: "key1"))
        XCTAssertNil(cache.access(forKey: "key2"))
    }
    
    // MARK: - Eviction
    
    func testEvictionByCount() {
        // Fill cache to capacity
        for i in 0..<5 {
            cache.insert(CacheEntry("value\(i)"), forKey: "key\(i)")
        }
        
        XCTAssertEqual(cache.count, 5)
        
        // Insert new item, should evict oldest
        cache.insert(CacheEntry("value5"), forKey: "key5")
        
        XCTAssertEqual(cache.count, 5)
        XCTAssertNil(cache.access(forKey: "key0"))
    }
    
    func testEvictionByCost() {
        let smallCache = LRUCache<String, String>(maxItemCount: 100, maxTotalCost: 10)
        
        // Insert items with default cost (1)
        for i in 0..<10 {
            smallCache.insert(CacheEntry("value\(i)"), forKey: "key\(i)")
        }
        
        // Should have evicted some items
        XCTAssertLessThanOrEqual(smallCache.totalCost, 10)
    }
    
    func testEvictionReturnsEvictedEntry() {
        for i in 0..<5 {
            cache.insert(CacheEntry("value\(i)"), forKey: "key\(i)")
        }
        
        let evicted = cache.insert(CacheEntry("value5"), forKey: "key5")
        XCTAssertNotNil(evicted)
        XCTAssertEqual(evicted?.value, "value0")
    }
    
    // MARK: - Expiration
    
    func testExpiredEntryNotAccessed() {
        let entry = CacheEntry("value1", expiration: 0.1)
        cache.insert(entry, forKey: "key1")
        
        // Should be accessible immediately
        XCTAssertNotNil(cache.access(forKey: "key1"))
        
        // Wait for expiration
        Thread.sleep(forTimeInterval: 0.15)
        
        // Should return nil for expired entry
        XCTAssertNil(cache.access(forKey: "key1"))
    }
    
    func testCleanupExpired() {
        // Insert items with different expiration times
        cache.insert(CacheEntry("value1", expiration: 0.1), forKey: "key1")
        cache.insert(CacheEntry("value2", expiration: 0.1), forKey: "key2")
        cache.insert(CacheEntry("value3"), forKey: "key3") // No expiration
        
        Thread.sleep(forTimeInterval: 0.15)
        
        let removed = cache.cleanupExpired()
        XCTAssertEqual(removed, 2)
        
        XCTAssertEqual(cache.count, 1)
        XCTAssertNotNil(cache.access(forKey: "key3"))
    }
    
    // MARK: - Cost Tracking
    
    func testTotalCost() {
        cache.insert(CacheEntry("value1", cost: 3), forKey: "key1")
        cache.insert(CacheEntry("value2", cost: 5), forKey: "key2")
        
        XCTAssertEqual(cache.totalCost, 8)
    }
    
    func testCostUpdatesOnRemove() {
        cache.insert(CacheEntry("value1", cost: 3), forKey: "key1")
        cache.insert(CacheEntry("value2", cost: 5), forKey: "key2")
        
        cache.remove(forKey: "key1")
        
        XCTAssertEqual(cache.totalCost, 5)
    }
    
    func testCostUpdatesOnEviction() {
        let smallCache = LRUCache<String, String>(maxItemCount: 2, maxTotalCost: 10)
        
        smallCache.insert(CacheEntry("value1", cost: 5), forKey: "key1")
        smallCache.insert(CacheEntry("value2", cost: 5), forKey: "key2")
        
        // Insert new item with cost 5, should evict key1
        smallCache.insert(CacheEntry("value3", cost: 5), forKey: "key3")
        
        XCTAssertEqual(smallCache.totalCost, 10)
        XCTAssertNil(smallCache.access(forKey: "key1"))
    }
    
    // MARK: - All Keys
    
    func testAllKeys() {
        cache.insert(CacheEntry("value1"), forKey: "key1")
        cache.insert(CacheEntry("value2"), forKey: "key2")
        cache.insert(CacheEntry("value3"), forKey: "key3")
        
        let keys = cache.allKeys
        XCTAssertEqual(keys.count, 3)
        XCTAssertTrue(keys.contains("key1"))
        XCTAssertTrue(keys.contains("key2"))
        XCTAssertTrue(keys.contains("key3"))
    }
    
    func testAllKeysExcludesExpired() {
        cache.insert(CacheEntry("value1", expiration: 0.1), forKey: "key1")
        cache.insert(CacheEntry("value2"), forKey: "key2")
        
        Thread.sleep(forTimeInterval: 0.15)
        
        let keys = cache.allKeys
        XCTAssertEqual(keys.count, 1)
        XCTAssertTrue(keys.contains("key2"))
    }
    
    // MARK: - Thread Safety
    
    func testConcurrentAccess() {
        let concurrentCache = LRUCache<String, Int>(maxItemCount: 100, maxTotalCost: 1000)
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 100
        
        for i in 0..<100 {
            queue.async {
                concurrentCache.insert(CacheEntry(i), forKey: "key\(i)")
                _ = concurrentCache.access(forKey: "key\(i)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertLessThanOrEqual(concurrentCache.count, 100)
    }
}
