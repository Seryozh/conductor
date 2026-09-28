import Foundation

/// A busy model can work for any duration. Only silence expires a request.
final class BrainIdleWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var lastActivity = ProcessInfo.processInfo.systemUptime
    private var timer: DispatchSourceTimer?
    private var active = true
    private var operations = Set<String>()

    init(timeout: TimeInterval, expired: @escaping () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        self.timer = timer
        timer.schedule(deadline: .now() + timeout, repeating: min(1, max(0.01, timeout / 4)))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let fire = self.lock.withLock { () -> Bool in
                guard self.active, self.operations.isEmpty, ProcessInfo.processInfo.systemUptime - self.lastActivity >= timeout else { return false }
                self.active = false
                return true
            }
            if fire { expired() }
        }
        timer.resume()
    }
    func activity() { lock.withLock { lastActivity = ProcessInfo.processInfo.systemUptime } }
    func begin(_ id: String) { lock.withLock { operations.insert(id); lastActivity = ProcessInfo.processInfo.systemUptime } }
    func end(_ id: String) { lock.withLock { operations.remove(id); lastActivity = ProcessInfo.processInfo.systemUptime } }
    func endAll() { lock.withLock { operations.removeAll(); lastActivity = ProcessInfo.processInfo.systemUptime } }
    func stop() {
        let timer = lock.withLock { () -> DispatchSourceTimer? in
            active = false
            let old = self.timer; self.timer = nil
            return old
        }
        timer?.cancel()
    }
    deinit { stop() }
}
