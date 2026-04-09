import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(MemoryCacheTests.allTests),
        testCase(DiskCacheTests.allTests),
        testCase(HybridCacheTests.allTests),
        testCase(LRUCacheTests.allTests),
        testCase(LockTests.allTests),
        testCase(CacheEntryTests.allTests),
        testCase(ExpirationManagerTests.allTests),
        testCase(AsyncIOTests.allTests)
    ]
}
#endif
