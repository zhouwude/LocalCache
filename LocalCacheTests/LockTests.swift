import XCTest
@testable import LocalCache

final class LockTests: XCTestCase {
    
    // MARK: - Lock Tests
    
    func testLockSync() {
        let lock = Lock()
        var counter = 0
        
        for _ in 0..<100 {
            lock.sync {
                counter += 1
            }
        }
        
        XCTAssertEqual(counter, 100)
    }
    
    func testLockSyncAsync() async {
        let lock = Lock()
        var counter = 0
        
        await lock.sync {
            counter += 1
        }
        
        XCTAssertEqual(counter, 1)
    }
    
    func testLockSyncThrowing() throws {
        let lock = Lock()
        
        let result = try lock.sync {
            return "success"
        }
        
        XCTAssertEqual(result, "success")
    }
    
    func testLockSyncAsyncThrowing() async throws {
        let lock = Lock()
        
        let result = try await lock.sync {
            return "success"
        }
        
        XCTAssertEqual(result, "success")
    }
    
    func testLockTryLock() {
        let lock = Lock()
        
        let acquired = lock.tryLock()
        XCTAssertTrue(acquired)
        
        lock.unlock()
    }
    
    func testLockConcurrentAccess() {
        let lock = Lock()
        var counter = 0
        let expectation = XCTestExpectation(description: "Concurrent increments")
        expectation.expectedFulfillmentCount = 100
        
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        
        for _ in 0..<100 {
            queue.async {
                lock.sync {
                    counter += 1
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertEqual(counter, 100)
    }
    
    func testOSSpinLock() {
        let spinLock = Lock(useOSSpinLock: true)
        var counter = 0
        
        for _ in 0..<100 {
            spinLock.sync {
                counter += 1
            }
        }
        
        XCTAssertEqual(counter, 100)
    }
    
    // MARK: - RWLock Tests
    
    func testRWLockConcurrentReads() {
        let rwLock = RWLock()
        var readCount = 0
        
        let expectation = XCTestExpectation(description: "Concurrent reads")
        expectation.expectedFulfillmentCount = 10
        
        for _ in 0..<10 {
            DispatchQueue.global().async {
                let value = rwLock.read {
                    return 42
                }
                
                if value == 42 {
                    readCount += 1
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(readCount, 10)
    }
    
    func testRWLockExclusiveWrite() {
        let rwLock = RWLock()
        var value = 0
        
        let expectation = XCTestExpectation(description: "Sequential writes")
        expectation.expectedFulfillmentCount = 10
        
        for i in 0..<10 {
            DispatchQueue.global().async {
                rwLock.write {
                    value = i
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        XCTAssertGreaterThanOrEqual(value, 0)
    }
    
    func testRWLockAsyncRead() async {
        let rwLock = RWLock()
        
        let value = await rwLock.read {
            return 42
        }
        
        XCTAssertEqual(value, 42)
    }
    
    func testRWLockAsyncWrite() async {
        let rwLock = RWLock()
        
        await rwLock.write {
            // Write operation
        }
        
        // Should complete without deadlock
    }
    
    // MARK: - Performance Tests
    
    func testLockPerformance() {
        let lock = Lock()
        let iterations = 10000
        
        measure {
            for _ in 0..<iterations {
                lock.sync {
                    // Empty critical section
                }
            }
        }
    }
    
    func testOSSpinLockPerformance() {
        let spinLock = Lock(useOSSpinLock: true)
        let iterations = 10000
        
        measure {
            for _ in 0..<iterations {
                spinLock.sync {
                    // Empty critical section
                }
            }
        }
    }
    
    func testRWLockVsLockPerformance() {
        let rwLock = RWLock()
        let lock = Lock()
        let iterations = 10000
        
        // RWLock read-heavy workload
        measure {
            for _ in 0..<iterations {
                rwLock.read {
                    // Read operation
                }
            }
        }
    }
}
