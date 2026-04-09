# LocalCache

高性能 iOS 本地缓存框架，支持内存缓存、磁盘缓存和混合缓存模式。

## 特性

- 🚀 **高性能**: 线程安全的 LRU 缓存实现
- 💾 **多级存储**: 内存缓存、磁盘缓存、混合缓存
- 🔒 **线程安全**: 支持 OSSpinLock 和 NSLock
- ⏰ **自动过期**: 灵活的过期策略和自动清理
- 🎯 **类型安全**: 完整的泛型支持
- 📊 **可观测性**: 支持观察者模式监控缓存事件
- 🔄 **Async/Await**: 完整的异步支持

## 安装

### Swift Package Manager

在 `Package.swift` 中添加:

```swift
dependencies: [
    .package(path: "./LocalCache")
]
```

或在 Xcode 中: File → Add Packages → 选择 LocalCache 文件夹

## 快速开始

### 内存缓存

```swift
import LocalCache

// 创建内存缓存
let cache = MemoryCache<String, String>(
    configuration: .memoryCache(maxItems: 100, maxCost: 1000)
)

// 设置值
try await cache.set("Hello", forKey: "greeting", expiration: 3600)

// 获取值
if let value = try await cache.get(forKey: "greeting") {
    print(value) // "Hello"
}

// 检查是否存在
if try await cache.contains(forKey: "greeting") {
    print("Key exists")
}

// 删除值
try await cache.remove(forKey: "greeting")

// 清空缓存
try await cache.removeAll()
```

### 磁盘缓存

```swift
import LocalCache

// 创建磁盘缓存
let cache = DiskCache<String, MyCodableStruct>(
    configuration: .diskCache(maxSize: 100 * 1024 * 1024)
)

// 准备缓存
try await cache.prepare()

// 设置值 (自动编码为 JSON)
let data = MyCodableStruct(name: "John", age: 30)
try await cache.set(data, forKey: "user-123", expiration: 86400)

// 获取值 (自动解码)
if let user = try await cache.get(forKey: "user-123") {
    print(user.name)
}
```

### 混合缓存

```swift
import LocalCache

// 创建混合缓存 (内存 + 磁盘)
let cache = HybridCache<String, MyCodableStruct>(
    configuration: .hybridCache(memoryItems: 50, diskSize: 100 * 1024 * 1024)
)

// 准备缓存
try await cache.prepare()

// 使用 (自动管理内存和磁盘)
try await cache.set(data, forKey: "key")
let value = try await cache.get(forKey: "key") // 先查内存，再查磁盘

// 强制刷新到磁盘
try await cache.flush()

// 获取统计信息
let stats = try await cache.statistics
print("Memory: \(stats.memoryCount), Disk: \(stats.diskCount)")
```

## 高级用法

### 自定义配置

```swift
let config = CacheConfiguration(
    maxItemCount: 200,           // 最大项目数
    maxTotalCost: 2000,          // 最大总成本
    defaultExpiration: 7200,     // 默认过期时间 (秒)
    autoCleanup: true,           // 自动清理过期项目
    maxDiskCacheSize: 200 * 1024 * 1024, // 最大磁盘大小
    queuePriority: .userInitiated // 队列优先级
)

let cache = MemoryCache<String, Data>(configuration: config)
```

### Get-Or-Set 模式

```swift
// 缓存不存在时自动创建
let user = try await cache.getOrSet(
    forKey: "user-123",
    factory: {
        // 从网络或数据库加载
        return try await fetchUserFromNetwork(id: "123")
    },
    expiration: 3600
)
```

### 观察者模式

```swift
// 添加观察者
let observerId = await cache.addObserver { event in
    switch event {
    case .set(let key):
        print("Set: \(key)")
    case .hit(let key):
        print("Cache hit: \(key)")
    case .miss(let key):
        print("Cache miss: \(key)")
    case .expired(let key):
        print("Expired: \(key)")
    case .remove(let key):
        print("Removed: \(key)")
    case .clear:
        print("Cache cleared")
    case .cleanup(let count):
        print("Cleaned up \(count) items")
    }
}

// 移除观察者
await cache.removeObserver(observerId)
```

### 过期策略

```swift
// 固定时间过期
let policy1 = ExpirationPolicy.after(3600) // 1 小时后过期

// 指定时间过期
let policy2 = ExpirationPolicy.at(Date().addingTimeInterval(86400))

// 基于访问时间过期
let policy3 = ExpirationPolicy.accessBased(3600) // 1 小时未访问后过期

// 永不过期
let policy4 = ExpirationPolicy.never
```

### 批量操作

```swift
// 并发执行多个缓存操作
let results = try await withThrowingTaskGroup(of: String?.self) { group in
    for key in ["key1", "key2", "key3"] {
        group.addTask {
            return try await cache.get(forKey: key)
        }
    }
    
    var results: [String?] = []
    for try await result in group {
        results.append(result)
    }
    return results
}
```

### 自定义键类型

```swift
// 支持任何 Hashable 类型作为键
struct UserID: Hashable {
    let id: String
}

let cache = MemoryCache<UserID, UserData>()
try await cache.set(user, forKey: UserID(id: "123"))
```

## 性能优化建议

1. **选择合适的缓存模式**:
   - 频繁访问的小数据 → 内存缓存
   - 大数据或不常访问 → 磁盘缓存
   - 平衡性能和持久化 → 混合缓存

2. **合理设置过期时间**:
   - 临时数据：60-300 秒
   - 会话数据：3600-86400 秒
   - 持久数据：0 (永不过期)

3. **使用合适的容量限制**:
   - 内存缓存：根据设备内存调整
   - 磁盘缓存：考虑用户存储空间

4. **定期清理**:
   ```swift
   // 应用启动时清理
   try await cache.cleanupExpired()
   
   // 或定期清理
   ExpirationManager.shared.schedule(cacheId: "myCache") {
       try? await cache.cleanupExpired()
   }
   ```

## 线程安全

所有缓存操作都是线程安全的:

```swift
// 可以在多个线程/任务中安全使用
Task {
    try await cache.set(value1, forKey: "key1")
}

Task {
    try await cache.set(value2, forKey: "key2")
}

Task {
    let v1 = try await cache.get(forKey: "key1")
    let v2 = try await cache.get(forKey: "key2")
}
```

## 错误处理

```swift
do {
    try await cache.set(value, forKey: "key")
} catch CacheError.encodingFailed(let reason) {
    print("编码失败：\(reason)")
} catch CacheError.diskIOError(let reason) {
    print("磁盘错误：\(reason)")
} catch CacheError.storageFull {
    print("存储空间已满")
} catch {
    print("其他错误：\(error)")
}
```

## 测试

运行测试:

```bash
cd LocalCache
swift test
```

## 文件结构

```
LocalCache/
├── Core/                      # 核心协议和类型
│   ├── CacheProtocol.swift    # 缓存协议定义
│   ├── CacheEntry.swift       # 缓存条目
│   ├── CacheError.swift       # 错误类型
│   └── CacheConfiguration.swift # 配置
├── Memory/                    # 内存缓存
│   ├── MemoryCache.swift      # 内存缓存实现
│   └── LRUCache.swift         # LRU 算法
├── Disk/                      # 磁盘缓存
│   ├── DiskCache.swift        # 磁盘缓存实现
│   ├── DiskCacheManager.swift # 磁盘管理
│   └── FileStorage.swift      # 文件存储
├── Hybrid/                    # 混合缓存
│   └── HybridCache.swift      # 混合缓存实现
├── Thread/                    # 线程安全
│   ├── Lock.swift             # 锁实现
│   └── DispatchQueue+Extension.swift
├── Utils/                     # 工具类
│   ├── ExpirationManager.swift # 过期管理
│   └── AsyncIO.swift          # 异步 IO
├── LocalCacheTests/           # 单元测试
├── Package.swift              # SPM 配置
└── README.md                  # 文档
```

## 系统要求

- iOS 15.0+
- macOS 13.0+
- watchOS 8.0+
- tvOS 15.0+
- Swift 5.9+

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request!

## 示例项目

查看 `LocalCacheTests/` 目录中的完整测试用例，了解更多使用示例。
