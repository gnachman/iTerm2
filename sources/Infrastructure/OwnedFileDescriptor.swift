//
//  OwnedFileDescriptor.swift
//  iTerm2
//
//  Owns a file descriptor and closes it exactly once: when close() is called, or when this object
//  is deallocated, whichever is first. Closing waits until nobody is using the descriptor, so its
//  number can't be reused while someone still reads, writes, or watches it.
//
//  Use the descriptor only within withFileDescriptor(_:) or while holding a Lease. A dispatch
//  source watching it should hold a lease until its cancel handler runs.
//

import Foundation

@objc(iTermOwnedFileDescriptor)
final class OwnedFileDescriptor: NSObject {
    // Keeps the descriptor open until it is released or deallocated, even if close() is called
    // meanwhile. It also keeps its OwnedFileDescriptor alive.
    final class Lease {
        let fileDescriptor: Int32
        private let owner: OwnedFileDescriptor
        private let released = MutableAtomicObject(false)

        fileprivate init(owner: OwnedFileDescriptor, fileDescriptor: Int32) {
            self.owner = owner
            self.fileDescriptor = fileDescriptor
        }

        deinit {
            release()
        }

        // Any thread. Safe to call more than once.
        func release() {
            if !released.getAndSet(true) {
                owner.endUse()
            }
        }
    }

    private struct State {
        // -1 once closing has been requested.
        var fileDescriptor: Int32
        // The descriptor to close once nothing is using it.
        let original: Int32
        var uses = 0
        var closed = false
    }
    private let state: MutableAtomicObject<State>
    private let closeFunction: (Int32) -> Int32

    // Takes ownership of `fileDescriptor`. A negative value means there is nothing to own.
    @objc(initWithFileDescriptor:)
    convenience init(_ fileDescriptor: Int32) {
        self.init(fileDescriptor, close: Darwin.close)
    }

    // Testing only: `close` stands in for close(2).
    init(_ fileDescriptor: Int32, close: @escaping (Int32) -> Int32) {
        state = MutableAtomicObject(State(fileDescriptor: fileDescriptor,
                                          original: fileDescriptor,
                                          closed: fileDescriptor < 0))
        closeFunction = close
        super.init()
    }

    deinit {
        // Leases keep this object alive, so nothing can be using the descriptor now.
        let fd = state.mutableAccess { state -> Int32? in
            guard !state.closed else {
                return nil
            }
            state.closed = true
            return state.original
        }
        if let fd {
            reallyClose(fd)
        }
    }

    override var description: String {
        return "<iTermOwnedFileDescriptor: \(Unmanaged.passUnretained(self).toOpaque()) fd=\(unsafeFileDescriptor)>"
    }

    // Any thread. The descriptor's number, or -1 once close() has been called. Doing I/O with it
    // can race a close, after which the number may belong to something else. Only TaskNotifier's
    // select loop uses it. Everything else uses withFileDescriptor(_:) or a lease.
    @objc var unsafeFileDescriptor: Int32 {
        return state.access { $0.fileDescriptor }
    }

    // Any thread. True once close() has been called, or if there was never a descriptor.
    @objc var isClosed: Bool {
        return state.access { $0.fileDescriptor < 0 }
    }

    // Any thread. Makes a pipe, returning its read end then its write end, or nil if pipe(2)
    // fails (errno says why). Neither end is nonblocking or closed on exec.
    @objc(pipe)
    static func makePipe() -> iTermTuple<OwnedFileDescriptor, OwnedFileDescriptor>? {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else {
            return nil
        }
        return iTermTuple(object: OwnedFileDescriptor(fds[0]), andObject: OwnedFileDescriptor(fds[1]))
    }

    // Any thread. Whether O_NONBLOCK is set. False once closed, and setting it then does nothing.
    @objc var nonblocking: Bool {
        get {
            return flag(get: F_GETFL, O_NONBLOCK)
        }
        set {
            setFlag(get: F_GETFL, set: F_SETFL, O_NONBLOCK, newValue)
        }
    }

    // Any thread. Whether FD_CLOEXEC is set. False once closed, and setting it then does nothing.
    @objc var closeOnExec: Bool {
        get {
            return flag(get: F_GETFD, FD_CLOEXEC)
        }
        set {
            setFlag(get: F_GETFD, set: F_SETFD, FD_CLOEXEC, newValue)
        }
    }

    private func flag(get: Int32, _ flag: Int32) -> Bool {
        var result = false
        withFileDescriptor { fd in
            let flags = fcntl(fd, get)
            result = flags >= 0 && (flags & flag) != 0
        }
        return result
    }

    private func setFlag(get: Int32, set: Int32, _ flag: Int32, _ value: Bool) {
        withFileDescriptor { fd in
            let flags = fcntl(fd, get)
            guard flags >= 0 else {
                let error = errno
                DLog("fcntl(\(fd), \(get)) failed: \(String(cString: strerror(error)))")
                return
            }
            let updated = value ? (flags | flag) : (flags & ~flag)
            if updated != flags && fcntl(fd, set, updated) < 0 {
                let error = errno
                DLog("fcntl(\(fd), \(set)) failed: \(String(cString: strerror(error)))")
            }
        }
    }

    // Any thread. Returns nil once close() has been called.
    func lease() -> Lease? {
        guard let fd = beginUse() else {
            return nil
        }
        return Lease(owner: self, fileDescriptor: fd)
    }

    // Any thread. Runs `block` with the descriptor, which stays open until it returns. Returns
    // false without running it once close() has been called.
    @objc(withFileDescriptor:)
    @discardableResult
    func withFileDescriptor(_ block: (Int32) -> Void) -> Bool {
        guard let fd = beginUse() else {
            return false
        }
        defer {
            endUse()
        }
        block(fd)
        return true
    }

    // Any thread. Closes the descriptor now, or once the last lease and withFileDescriptor(_:)
    // block are done. Safe to call more than once.
    @objc
    func close() {
        let fd = state.mutableAccess { state -> Int32? in
            state.fileDescriptor = -1
            return takeDescriptorToClose(&state)
        }
        if let fd {
            reallyClose(fd)
        }
    }

    // MARK: - Private

    private func beginUse() -> Int32? {
        return state.mutableAccess { state -> Int32? in
            guard state.fileDescriptor >= 0 else {
                return nil
            }
            state.uses += 1
            return state.fileDescriptor
        }
    }

    private func endUse() {
        let fd = state.mutableAccess { state -> Int32? in
            it_assert(state.uses > 0, "Ended more uses than began")
            state.uses -= 1
            return takeDescriptorToClose(&state)
        }
        if let fd {
            reallyClose(fd)
        }
    }

    // Call without the state locked. Never retried: on Darwin (as on Linux) the descriptor is
    // released even if close(2) fails, including with EINTR, and by then its number may belong to
    // someone else.
    private func reallyClose(_ fd: Int32) {
        if closeFunction(fd) != 0 {
            let error = errno
            // EBADF means something else closed a descriptor this object owns. That is a bug that
            // can make I/O go to whatever file reused the number, so don't let it go unnoticed.
            it_assert(error != EBADF, "close(\(fd)) failed with EBADF: it was already closed")
            if error != EINTR {
                RLog("close(\(fd)) failed with errno \(error)")
            }
        }
    }

    // Call with the state locked. Returns the descriptor if it should be closed now.
    private func takeDescriptorToClose(_ state: inout State) -> Int32? {
        guard state.fileDescriptor < 0, state.uses == 0, !state.closed else {
            return nil
        }
        state.closed = true
        return state.original
    }
}
