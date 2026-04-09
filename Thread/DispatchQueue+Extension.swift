import Foundation

/// Extension for DispatchQueue with async/await support
extension DispatchQueue {

    

    
    /// Delay execution by a specified time
    /// - Parameters:
    ///   - delay: Delay in seconds
    ///   - qos: Quality of service
    ///   - work: The work to execute
    public func asyncAfter(delay: TimeInterval, qos: DispatchQoS = .utility, execute work: @escaping () -> Void) {
        asyncAfter(deadline: .now() + delay, qos: qos, execute: work)
    }
    
}




