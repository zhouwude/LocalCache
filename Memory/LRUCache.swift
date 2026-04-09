import Foundation

/// Thread-safe LRU (Least Recently Used) Cache implementation
public final class LRUCache<Key: Hashable, Value> {
    private var cache: [Key: CacheEntry<Value>] = [:]
    private var order: [Key] = [] // Tracks access order (front = most recent)
    private var orderIndex: [Key: Int] = [:] // O(1) lookup for order array index
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
            if let oldEntry = cache[key] {
                removeKeyFromOrder(key)
                currentCost -= oldEntry.cost
                // orderIndex is already cleared by removeKeyFromOrder
            }
            
            // Evict if necessary
            var evicted: CacheEntry<Value>? = nil
            while (cache.count >= maxItemCount || currentCost + entry.cost > maxTotalCost) && !order.isEmpty {
                let lruKey = order.removeLast()
                orderIndex.removeValue(forKey: lruKey)
                if let lruEntry = cache.removeValue(forKey: lruKey) {
                    currentCost -= lruEntry.cost
                    if evicted == nil {
                        evicted = lruEntry
                    }
                }
            }
            
            // Insert new entry
            cache[key] = entry
            insertKeyAtFront(key)
            currentCost += entry.cost
            
            return evicted
        }
    }
    
    /// Access a value by key (marks as recently used)
    /// - Parameter key: The key
    /// - Returns: The cache entry if found
    public func access(forKey key: Key) -> CacheEntry<Value>? {
        lock.sync {
            guard let entry = cache[key], !entry.isExpired else {
                if cache[key] != nil {
                    removeKeyFromOrder(key)
                    cache[key] = nil
                }
                return nil
            }
            
            // Move to front (most recently used)
            removeKeyFromOrder(key)
            insertKeyAtFront(key)
            
            return entry
        }
    }
    
    /// Remove a key from the cache
    /// - Parameter key: The key
    /// - Returns: The removed entry if any
    @discardableResult
    public func remove(forKey key: Key) -> CacheEntry<Value>? {
        lock.sync {
            guard let entry = cache.removeValue(forKey: key) else {
                return nil
            }
            removeKeyFromOrder(key)
            currentCost -= entry.cost
            return entry
        }
    }
    
    /// Remove all entries
    public func removeAll() {
        lock.sync {
            cache.removeAll()
            order.removeAll()
            orderIndex.removeAll()
            currentCost = 0
        }
    }
    
    /// Check if key exists
    /// - Parameter key: The key
    /// - Returns: true if exists and not expired
    public func contains(forKey key: Key) -> Bool {
        lock.sync {
            guard let entry = cache[key] else { return false }
            return !entry.isExpired
        }
    }
    
    /// Get all keys (excluding expired)
    public var allKeys: [Key] {
        lock.sync {
            return order.filter { key in
                cache[key]?.isExpired == false
            }
        }
    }
    
    /// Cleanup expired entries
    /// - Returns: Number of entries removed
    @discardableResult
    public func cleanupExpired() -> Int {
        lock.sync {
            var removed = 0
            let expiredKeys = order.filter { key in
                cache[key]?.isExpired == true
            }
            
            for key in expiredKeys {
                if let entry = cache.removeValue(forKey: key) {
                    removeKeyFromOrder(key)
                    currentCost -= entry.cost
                    removed += 1
                }
            }
            
            return removed
        }
    }
    
    // MARK: - Private Methods
    
    private func removeKeyFromOrder(_ key: Key) {
        guard let index = orderIndex[key] else { return }
        order.remove(at: index)
        orderIndex.removeValue(forKey: key)
        
        // Update indices for all elements after the removed one
        for i in index..<order.count {
            orderIndex[order[i]] = i
        }
    }
    
    private func insertKeyAtFront(_ key: Key) {
        order.insert(key, at: 0)
        orderIndex[key] = 0
        
        // Update indices for all elements after the inserted one
        for i in 1..<order.count {
            orderIndex[order[i]] = i
        }
    }
}
