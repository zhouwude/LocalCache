import XCTest
@testable import LocalCache

final class CacheEntryTests: XCTestCase {
    
    // MARK: - Basic Properties
    
    func testEntryCreation() {
        let entry = CacheEntry("value")
        
        XCTAssertEqual(entry.value, "value")
        XCTAssertNotNil(entry.createdAt)
        XCTAssertNil(entry.expiresAt)
        XCTAssertEqual(entry.cost, 1)
    }
    
    func testEntryWithExpiration() {
        let entry = CacheEntry("value", expiration: 3600)
        
        XCTAssertEqual(entry.value, "value")
        XCTAssertNotNil(entry.expiresAt)
        XCTAssertTrue(entry.expiresAt! > Date())
    }
    
    func testEntryWithCost() {
        let entry = CacheEntry("value", cost: 10)
        
        XCTAssertEqual(entry.cost, 10)
    }
    
    // MARK: - Expiration Checks
    
    func testIsExpired() {
        let noExpiration = CacheEntry("value")
        XCTAssertFalse(noExpiration.isExpired)
        
        let futureExpiration = CacheEntry("value", expiration: 3600)
        XCTAssertFalse(futureExpiration.isExpired)
        
        let pastExpiration = CacheEntry("value", expiration: -1)
        XCTAssertTrue(pastExpiration.isExpired)
    }
    
    func testIsValid() {
        let valid = CacheEntry("value", expiration: 3600)
        XCTAssertTrue(valid.isValid)
        
        let expired = CacheEntry("value", expiration: -1)
        XCTAssertFalse(expired.isValid)
    }
    
    func testTimeToLive() {
        let noExpiration = CacheEntry("value")
        XCTAssertNil(noExpiration.timeToLive)
        
        let withExpiration = CacheEntry("value", expiration: 100)
        let ttl = withExpiration.timeToLive
        XCTAssertNotNil(ttl)
        XCTAssertGreaterThan(ttl!, 0)
        XCTAssertLessThanOrEqual(ttl!, 100)
    }
    
    func testTimeToLiveExpired() {
        let expired = CacheEntry("value", expiration: -1)
        let ttl = expired.timeToLive
        XCTAssertEqual(ttl, 0)
    }
    
    // MARK: - Refresh
    
    func testRefresh() {
        let original = CacheEntry("value", expiration: 100, cost: 5)
        
        Thread.sleep(forTimeInterval: 0.1)
        
        let refreshed = original.refresh()
        
        XCTAssertEqual(refreshed.value, original.value)
        XCTAssertEqual(refreshed.cost, original.cost)
        XCTAssertTrue(refreshed.createdAt > original.createdAt)
    }
    
    func testRefreshWithNewExpiration() {
        let original = CacheEntry("value", expiration: 100)
        let refreshed = original.refresh(expiration: 200)
        
        XCTAssertNotNil(refreshed.expiresAt)
        if let expiresAt = refreshed.expiresAt {
            let expectedExpiry = refreshed.createdAt.addingTimeInterval(200)
            XCTAssertEqual(expiresAt.timeIntervalSince(expectedExpiry), 0, accuracy: 0.1)
        }
    }
    
    // MARK: - Codable Data Entry
    
    func testFromCodable() throws {
        struct TestModel: Codable {
            let id: Int
            let name: String
        }
        
        let model = TestModel(id: 1, name: "Test")
        let entry = try CacheEntry.fromCodable(model, expiration: 3600, cost: 10)
        
        XCTAssertGreaterThan(entry.value.count, 0)
        XCTAssertEqual(entry.cost, 10)
        XCTAssertNotNil(entry.expiresAt)
    }
    
    func testDecode() throws {
        struct TestModel: Codable, Equatable {
            let id: Int
            let name: String
        }
        
        let original = TestModel(id: 1, name: "Test")
        let entry = try CacheEntry.fromCodable(original)
        
        let decoded = try entry.decode(as: TestModel.self)
        XCTAssertEqual(decoded, original)
    }
    
    func testDecodeFailure() throws {
        struct Model1: Codable {
            let id: Int
        }
        
        struct Model2: Codable {
            let name: String
        }
        
        let entry = try CacheEntry.fromCodable(Model1(id: 1))
        
        XCTAssertThrowsError(try entry.decode(as: Model2.self))
    }
    
    // MARK: - Performance
    
    func testEntryCreationPerformance() {
        measure {
            for _ in 0..<10000 {
                _ = CacheEntry("value", expiration: 3600, cost: 1)
            }
        }
    }
    
    func testCodableEntryPerformance() throws {
        struct TestModel: Codable {
            let id: Int
            let name: String
            let data: Data
        }
        
        let model = TestModel(id: 1, name: "Test", data: Data(repeating: 0, count: 100))
        
        measure {
            for _ in 0..<1000 {
                _ = try! CacheEntry.fromCodable(model)
            }
        }
    }
}
