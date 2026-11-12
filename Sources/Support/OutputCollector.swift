import Foundation

/// Thread-safe accumulator for process output.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    /// Appends a chunk of output.
    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    /// Returns everything collected so far.
    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
