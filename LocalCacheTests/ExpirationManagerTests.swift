import XCTest
@testable import LocalCache

final class ExpirationManagerTests: XCTestCase {
    var manager: ExpirationManager!
    
    override func setUp() {
        manager = ExpirationManager.shared
    }
    
    override func tearDown() {
        // Cancel all tasks after test
        manager.cancelAll()
    }
    
    // MARK: - Scheduling
    
    func testScheduleAndCancel() {
        let expectation = XCTestExpectation(description: "Cleanup called")
        expectation.expectedFulfillmentCount = 2
        
        var callCount = 0
        
        manager.schedule(cacheId: "test-cache-1", interval: 0.1) {
            callCount += 1
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        manager.cancel(cacheId: "test-cache-1")
    }
    
    func testCancelStopsCleanup() async throws {
        var callCount = 0
        
        manager.schedule(cacheId: "test-cache-2", interval: 0.1) {
            callCount += 1
        }
        
        // Wait for first call
        try await Task.sleep(nanoseconds: 150_000_000)
        let firstCount = callCount
        
        manager.cancel(cacheId: "test-cache-2")
        
        // Wait and verify no more calls
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(callCount, firstCount)
    }
    
    // MARK: - Next Expiration
    
    func testNextExpiration() {
        let entries: [String: CacheEntry<String>] = [
            "key1": CacheEntry("value1", expiration: 100),
            "key2": CacheEntry("value2", expiration: 200),
            "key3": CacheEntry("value3", expiration: 50)
        ]
        
        let next = manager.nextExpiration(for: entries)
        XCTAssertNotNil(next)
        
        // Should be the earliest expiration
        if let next = next {
            let expectedMin = Date().addingTimeInterval(50)
            XCTAssertEqual(next.timeIntervalSince(expectedMin), 0, accuracy: 1.0)
        }
    }
    
    func testNextExpirationWithExpired() {
        let entries: [String: CacheEntry<String>] = [
            "key1": CacheEntry("value1", expiration: -100), // Already expired
            "key2": CacheEntry("value2", expiration: 100),
            "key3": CacheEntry("value3", expiration: 200)
        ]
        
        let next = manager.nextExpiration(for: entries)
        XCTAssertNotNil(next)
        
        // Should ignore expired entries
        if let next = next {
            XCTAssertTrue(next > Date())
        }
    }
    
    func testNextExpirationNever() {
        let entries: [String: CacheEntry<String>] = [
            "key1": CacheEntry("value1"), // No expiration
            "key2": CacheEntry("value2")
        ]
        
        let next = manager.nextExpiration(for: entries)
        XCTAssertNil(next)
    }
    
    // MARK: - Expiring Soon
    
    func testExpiringSoon() {
        let entries: [String: CacheEntry<String>] = [
            "key1": CacheEntry("value1", expiration: 10),  // Expiring soon
            "key2": CacheEntry("value2", expiration: 30),  // Expiring soon
            "key3": CacheEntry("value3", expiration: 300), // Not expiring soon
            "key4": CacheEntry("value4")                    // Never expires
        ]
        
        let expiring = manager.expiringSoon(in: entries, within: 60)
        
        XCTAssertEqual(expiring.count, 2)
        XCTAssertTrue(expiring.contains("key1"))
        XCTAssertTrue(expiring.contains("key2"))
    }
    
    func testExpiringSoonNone() {
        let entries: [String: CacheEntry<String>] = [
            "key1": CacheEntry("value1", expiration: 3600),
            "key2": CacheEntry("value2", expiration: 7200)
        ]
        
        let expiring = manager.expiringSoon(in: entries, within: 60)
        XCTAssertEqual(expiring.count, 0)
    }
    
    // MARK: - Optimal Cleanup Interval
    
    func testOptimalCleanupInterval() {
        let entries: [String: CacheEntry<String>] = [
            "key1": CacheEntry("value1", expiration: 100),
            "key2": CacheEntry("value2", expiration: 200),
            "key3": CacheEntry("value3", expiration: 300)
        ]
        
        let interval = manager.optimalCleanupInterval(for: entries)
        
        // Should be between 30 and 600 seconds
        XCTAssertGreaterThanOrEqual(interval, 30)
        XCTAssertLessThanOrEqual(interval, 600)
    }
    
    func testOptimalCleanupIntervalNoExpirations() {
        let entries: [String: CacheEntry<String>] = [
            "key1": CacheEntry("value1"),
            "key2": CacheEntry("value2")
        ]
        
        let interval = manager.optimalCleanupInterval(for: entries)
        XCTAssertEqual(interval, 3600) // Default hourly
    }
    
    func testOptimalCleanupIntervalEmpty() {
        let entries: [String: CacheEntry<String>] = [:]
        
        let interval = manager.optimalCleanupInterval(for: entries)
        XCTAssertEqual(interval, 300) // Default 5 minutes
    }
    
    // MARK: - Expiration Policy
    
    func testExpirationPolicyNever() {
        let policy = ExpirationPolicy.never
        XCTAssertNil(policy.expirationDate())
    }
    
    func testExpirationPolicyAfter() {
        let policy = ExpirationPolicy.after(3600)
        let date = policy.expirationDate()
        
        XCTAssertNotNil(date)
        if let date = date {
            let expected = Date().addingTimeInterval(3600)
            XCTAssertEqual(date.timeIntervalSince(expected), 0, accuracy: 1.0)
        }
    }
    
    func testExpirationPolicyAt() {
        let specificDate = Date().addingTimeInterval(7200)
        let policy = ExpirationPolicy.at(specificDate)
        let date = policy.expirationDate()
        
        XCTAssertEqual(date, specificDate)
    }
    
    func testExpirationPolicyAccessBased() {
        let lastAccess = Date().addingTimeInterval(-10)
        let policy = ExpirationPolicy.accessBased(3600)
        let date = policy.expirationDate(lastAccessed: lastAccess)
        
        XCTAssertNotNil(date)
        if let date = date {
            let expected = lastAccess.addingTimeInterval(3600)
            XCTAssertEqual(date.timeIntervalSince(expected), 0, accuracy: 1.0)
        }
    }
}
