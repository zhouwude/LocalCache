import Foundation

/// Thread-safe lock abstraction
public final class Lock {
    private let _lock: NSLock
    private let useOSSpinLock: Bool
    
    #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    private var osSpinLock: os_unfair_lock_t?
    #endif
    
    /// Initialize lock
    /// - Parameter useOSSpinLock: Whether to use OSSpinLock (faster for short critical sections)
    public init(useOSSpinLock: Bool = false) {
        self.useOSSpinLock = useOSSpinLock
        self._lock = NSLock()
        
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        if useOSSpinLock {
            self.osSpinLock = .allocate(capacity: 1)
            self.osSpinLock?.initialize(to: os_unfair_lock())
        }
        #endif
    }
    
    deinit {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        if useOSSpinLock {
            self.osSpinLock?.deinitialize(count: 1)
            self.osSpinLock?.deallocate()
        }
        #endif
    }
    
    /// Execute a closure while holding the lock
    /// - Parameter closure: The closure to execute
    /// - Returns: The result of the closure
    public func sync<T>(_ closure: () -> T) -> T {
        lock()
        defer { unlock() }
        return closure()
    }
    
    /// Execute an async closure while holding the lock
    /// - Parameter closure: The async closure to execute
    /// - Returns: The result of the closure
    public func sync<T>(_ closure: () async -> T) async -> T {
        lock()
        defer { unlock() }
        return await closure()
    }
    
    /// Execute a throwing closure while holding the lock
    /// - Parameter closure: The closure to execute
    /// - Returns: The result of the closure
    /// - Throws: Any error thrown by the closure
    public func sync<T>(_ closure: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try closure()
    }
    
    /// Execute an async throwing closure while holding the lock
    /// - Parameter closure: The async closure to execute
    /// - Returns: The result of the closure
    /// - Throws: Any error thrown by the closure
    public func sync<T>(_ closure: () async throws -> T) async rethrows -> T {
        lock()
        defer { unlock() }
        return try await closure()
    }
    
    /// Lock the mutex
    public func lock() {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        if useOSSpinLock, let spinLock = osSpinLock {
            os_unfair_lock_lock(spinLock)
            return
        }
        #endif
        _lock.lock()
    }
    
    /// Unlock the mutex
    public func unlock() {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        if useOSSpinLock, let spinLock = osSpinLock {
            os_unfair_lock_unlock(spinLock)
            return
        }
        #endif
        _lock.unlock()
    }
    
    /// Try to lock the mutex
    /// - Returns: true if successfully locked
    public func tryLock() -> Bool {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        if useOSSpinLock, let spinLock = osSpinLock {
            return os_unfair_lock_trylock(spinLock)
        }
        #endif
        return _lock.try()
    }
}

/// Reader-Writer lock for better concurrent read performance
public final class RWLock {
    private let queue = DispatchQueue(
        label: "com.localcache.rwlock",
        attributes: .concurrent
    )
    
    /// Execute a read closure (multiple readers allowed)
    /// - Parameter closure: The closure to execute
    /// - Returns: The result of the closure
    public func read<T>(_ closure: () -> T) -> T {
        return queue.sync { closure() }
    }
    
    /// Execute a write closure (exclusive access)
    /// - Parameter closure: The closure to execute
    /// - Returns: The result of the closure
    public func write<T>(_ closure: () -> T) -> T {
        return queue.sync(flags: .barrier) { closure() }
    }
    
}
