import Foundation

/// Doubly linked list node for O(1) LRU operations
private final class LRUNode<Key: Hashable, Value> {
    let key: Key
    let entry: CacheEntry<Value>
    var prev: LRUNode?
    var next: LRUNode?

    init(key: Key, entry: CacheEntry<Value>) {
        self.key = key
        self.entry = entry
    }
}

/// Thread-safe LRU (Least Recently Used) Cache implementation
/// Uses a doubly linked list + hashmap for O(1) access and eviction
public final class LRUCache<Key: Hashable, Value> {
    private var cache: [Key: LRUNode<Key, Value>] = [:]
    private var head: LRUNode<Key, Value>? // Most recently used (front)
    private var tail: LRUNode<Key, Value>? // Least recently used (back)
    private let lock: Lock
    private var currentCost: Int = 0

    /// Maximum number of items
    public let maxItemCount: Int

    /// Maximum total cost
    public let maxTotalCost: Int

    /// Current number of items
    public var count: Int {
        lock.sync { cache.count }
    }

    /// Current total cost
    public var totalCost: Int {
        lock.sync { currentCost }
    }

    /// Initialize LRU cache
    /// - Parameters:
    ///   - maxItemCount: Maximum number of items
    ///   - maxTotalCost: Maximum total cost
    ///   - useOSSpinLock: Whether to use OSSpinLock (false = use NSLock)
    public init(maxItemCount: Int = 100, maxTotalCost: Int = 1000, useOSSpinLock: Bool = false) {
        self.maxItemCount = maxItemCount
        self.maxTotalCost = maxTotalCost
        self.lock = Lock(useOSSpinLock: useOSSpinLock)
    }

    /// Insert a value into the cache
    /// - Parameters:
    ///   - entry: The cache entry to insert
    ///   - key: The key
    /// - Returns: The evicted entry if any
    @discardableResult
    public func insert(_ entry: CacheEntry<Value>, forKey key: Key) -> CacheEntry<Value>? {
        lock.sync {
            // If key exists, remove old entry first
            if let existingNode = cache[key] {
                removeNode(existingNode)
                currentCost -= existingNode.entry.cost
            }

            // Create new node
            let newNode = LRUNode(key: key, entry: entry)

            // Evict if necessary
            var evicted: CacheEntry<Value>? = nil
            while (cache.count >= maxItemCount || currentCost + entry.cost > maxTotalCost), let lruNode = tail {
                removeNode(lruNode)
                currentCost -= lruNode.entry.cost
                if evicted == nil {
                    evicted = lruNode.entry
                }
            }

            // Insert new entry at front (most recently used)
            addToFront(newNode)
            cache[key] = newNode
            currentCost += entry.cost

            return evicted
        }
    }

    /// Access a value by key (marks as recently used)
    /// - Parameter key: The key
    /// - Returns: The cache entry if found
    public func access(forKey key: Key) -> CacheEntry<Value>? {
        lock.sync {
            guard let node = cache[key], !node.entry.isExpired else {
                if let node = cache[key] {
                    removeNode(node)
                    cache[key] = nil
                }
                return nil
            }

            // Move to front (most recently used)
            moveToFront(node)
            return node.entry
        }
    }

    /// Remove a key from the cache
    /// - Parameter key: The key
    /// - Returns: The removed entry if any
    @discardableResult
    public func remove(forKey key: Key) -> CacheEntry<Value>? {
        lock.sync {
            guard let node = cache.removeValue(forKey: key) else {
                return nil
            }
            removeNode(node)
            currentCost -= node.entry.cost
            return node.entry
        }
    }

    /// Remove all entries
    public func removeAll() {
        lock.sync {
            cache.removeAll()
            head = nil
            tail = nil
            currentCost = 0
        }
    }

    /// Check if key exists
    /// - Parameter key: The key
    /// - Returns: true if exists and not expired
    public func contains(forKey key: Key) -> Bool {
        lock.sync {
            guard let node = cache[key] else { return false }
            return !node.entry.isExpired
        }
    }

    /// Get all keys (excluding expired)
    public var allKeys: [Key] {
        lock.sync {
            var keys: [Key] = []
            var current = head
            while let node = current {
                if !node.entry.isExpired {
                    keys.append(node.key)
                }
                current = node.next
            }
            return keys
        }
    }

    /// Cleanup expired entries
    /// - Returns: Number of entries removed
    @discardableResult
    public func cleanupExpired() -> Int {
        lock.sync {
            var removed = 0
            var expiredKeys: [Key] = []

            var current = head
            while let node = current {
                if node.entry.isExpired {
                    expiredKeys.append(node.key)
                }
                current = node.next
            }

            for key in expiredKeys {
                if let node = cache.removeValue(forKey: key) {
                    removeNode(node)
                    currentCost -= node.entry.cost
                    removed += 1
                }
            }

            return removed
        }
    }

    // MARK: - Private Linked List Methods

    /// Remove a node from the linked list
    private func removeNode(_ node: LRUNode<Key, Value>) {
        if node === head {
            head = node.next
        } else {
            node.prev?.next = node.next
        }

        if node === tail {
            tail = node.prev
        } else {
            node.next?.prev = node.prev
        }

        node.prev = nil
        node.next = nil
    }

    /// Add a node to the front (most recently used)
    private func addToFront(_ node: LRUNode<Key, Value>) {
        node.next = head
        node.prev = nil
        head?.prev = node
        head = node

        if tail == nil {
            tail = node
        }
    }

    /// Move an existing node to the front
    private func moveToFront(_ node: LRUNode<Key, Value>) {
        guard node !== head else { return } // Already at front
        removeNode(node)
        addToFront(node)
    }
}
