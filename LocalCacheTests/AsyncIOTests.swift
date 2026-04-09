import XCTest
@testable import LocalCache

final class AsyncIOTests: XCTestCase {
    var tempDirectory: URL!
    
    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AsyncIOTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    // MARK: - Read/Write Data
    
    func testWriteAndReadData() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test.dat")
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        
        try await AsyncIO.write(to: fileURL, data: testData)
        let readData = try await AsyncIO.read(from: fileURL)
        
        XCTAssertEqual(readData, testData)
    }
    
    func testReadNonExistentFile() async {
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.dat")
        
        await XCTAssertThrowsErrorAsync(try await AsyncIO.read(from: fileURL))
    }
    
    // MARK: - Read/Write String
    
    func testWriteAndReadString() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        let testString = "Hello, World! 🌍"
        
        try await AsyncIO.writeString(to: fileURL, string: testString)
        let readString = try await AsyncIO.readString(from: fileURL)
        
        XCTAssertEqual(readString, testString)
    }
    
    func testReadStringWithEncoding() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test-utf16.txt")
        let testString = "Hello, 世界"
        
        let data = testString.data(using: .utf16)!
        try await AsyncIO.write(to: fileURL, data: data)
        
        let readString = try await AsyncIO.readString(from: fileURL, encoding: .utf16)
        XCTAssertEqual(readString, testString)
    }
    
    // MARK: - File Existence
    
    func testFileExists() async throws {
        let fileURL = tempDirectory.appendingPathComponent("exists.txt")
        try await AsyncIO.writeString(to: fileURL, string: "test")
        
        let exists = await AsyncIO.exists(at: fileURL)
        XCTAssertTrue(exists)
        
        let notExists = await AsyncIO.exists(at: tempDirectory.appendingPathComponent("notexists.txt"))
        XCTAssertFalse(notExists)
    }
    
    // MARK: - File Attributes
    
    func testFileAttributes() async throws {
        let fileURL = tempDirectory.appendingPathComponent("attrs.txt")
        try await AsyncIO.writeString(to: fileURL, string: "test content")
        
        let attributes = try await AsyncIO.attributes(of: fileURL)
        XCTAssertNotNil(attributes[.size])
        XCTAssertNotNil(attributes[.creationDate])
        XCTAssertNotNil(attributes[.modificationDate])
    }
    
    func testFileSize() async throws {
        let fileURL = tempDirectory.appendingPathComponent("size.txt")
        let content = "Test content with specific size"
        try await AsyncIO.writeString(to: fileURL, string: content)
        
        let size = await AsyncIO.fileSize(at: fileURL)
        XCTAssertNotNil(size)
        XCTAssertEqual(size, Int64(content.count))
    }
    
    func testFileSizeNonExistent() async {
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.txt")
        let size = await AsyncIO.fileSize(at: fileURL)
        XCTAssertNil(size)
    }
    
    // MARK: - Remove File
    
    func testRemoveFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("toremove.txt")
        try await AsyncIO.writeString(to: fileURL, string: "test")
        
        try await AsyncIO.remove(at: fileURL)
        
        let exists = await AsyncIO.exists(at: fileURL)
        XCTAssertFalse(exists)
    }
    
    func testRemoveNonExistentFile() async {
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.txt")
        
        await XCTAssertThrowsErrorAsync(try await AsyncIO.remove(at: fileURL))
    }
    
    // MARK: - Move File
    
    func testMoveFile() async throws {
        let sourceURL = tempDirectory.appendingPathComponent("source.txt")
        let destURL = tempDirectory.appendingPathComponent("dest.txt")
        
        try await AsyncIO.writeString(to: sourceURL, string: "test content")
        try await AsyncIO.move(from: sourceURL, to: destURL)
        
        let sourceExists = await AsyncIO.exists(at: sourceURL)
        let destExists = await AsyncIO.exists(at: destURL)
        
        XCTAssertFalse(sourceExists)
        XCTAssertTrue(destExists)
        
        let content = try await AsyncIO.readString(from: destURL)
        XCTAssertEqual(content, "test content")
    }
    
    // MARK: - Copy File
    
    func testCopyFile() async throws {
        let sourceURL = tempDirectory.appendingPathComponent("source.txt")
        let destURL = tempDirectory.appendingPathComponent("dest.txt")
        
        try await AsyncIO.writeString(to: sourceURL, string: "test content")
        try await AsyncIO.copy(from: sourceURL, to: destURL)
        
        let sourceExists = await AsyncIO.exists(at: sourceURL)
        let destExists = await AsyncIO.exists(at: destURL)
        
        XCTAssertTrue(sourceExists)
        XCTAssertTrue(destExists)
        
        let sourceContent = try await AsyncIO.readString(from: sourceURL)
        let destContent = try await AsyncIO.readString(from: destURL)
        
        XCTAssertEqual(sourceContent, destContent)
    }
    
    // MARK: - Async File Stream
    
    func testAsyncFileStream() async throws {
        let fileURL = tempDirectory.appendingPathComponent("stream.txt")
        let largeContent = String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZ", count: 100)
        try await AsyncIO.writeString(to: fileURL, string: largeContent)
        
        let stream = AsyncFileStream(url: fileURL, chunkSize: 64)
        var readContent = Data()
        
        for try await chunk in stream {
            readContent.append(chunk)
        }
        
        let result = String(data: readContent, encoding: .utf8)
        XCTAssertEqual(result, largeContent)
    }
    
    func testAsyncFileStreamEmptyFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("empty.txt")
        try await AsyncIO.writeString(to: fileURL, string: "")
        
        let stream = AsyncFileStream(url: fileURL)
        var chunkCount = 0
        
        for try await _ in stream {
            chunkCount += 1
        }
        
        XCTAssertEqual(chunkCount, 0)
    }
    
    // MARK: - Concurrent Access
    
    func testConcurrentReadWrite() async throws {
        let fileURL = tempDirectory.appendingPathComponent("concurrent.txt")
        
        let group = TaskGroup<Void>()
        
        // Multiple writers
        for i in 0..<10 {
            group.addTask {
                try? await AsyncIO.writeString(to: fileURL, string: "write-\(i)")
            }
        }
        
        // Multiple readers
        for _ in 0..<10 {
            group.addTask {
                _ = try? await AsyncIO.readString(from: fileURL)
            }
        }
        
        await group.waitForAll()
        
        // File should exist and be readable
        let exists = await AsyncIO.exists(at: fileURL)
        XCTAssertTrue(exists)
    }
    
    // MARK: - Performance
    
    func testWritePerformance() async throws {
        let fileURL = tempDirectory.appendingPathComponent("perf.txt")
        let data = Data(repeating: 0x42, count: 1024 * 1024) // 1MB
        
        measure {
            let expectation = XCTestExpectation(description: "Write complete")
            
            Task {
                try? await AsyncIO.write(to: fileURL, data: data)
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    func testReadPerformance() async throws {
        let fileURL = tempDirectory.appendingPathComponent("perf.txt")
        let data = Data(repeating: 0x42, count: 1024 * 1024) // 1MB
        try await AsyncIO.write(to: fileURL, data: data)
        
        measure {
            let expectation = XCTestExpectation(description: "Read complete")
            
            Task {
                _ = try? await AsyncIO.read(from: fileURL)
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
}

// MARK: - Helper

func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("Expected error but succeeded", file: file, line: line)
    } catch {
        // Expected
    }
}
