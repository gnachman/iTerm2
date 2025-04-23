//
//  FileDescriptorMonitor.swift
//  iTerm2
//
//  Created by George Nachman on 4/13/25.
//

import Foundation

@objc(iTermFileDescriptorMonitor)
class FileDescriptorMonitor: NSObject {
    static let queue = DispatchQueue(label: "com.iterm2.channels")
    struct Notification: CustomDebugStringConvertible {
        var debugDescription: String {
            "<FileDescriptorMonitor.Notification fd=\(fileDescriptor) readable=\(isReadable) writable=\(isWritable)>"
        }
        var fileDescriptor: Int32
        var isReadable: Bool
        var isWritable: Bool
    }

    typealias Observer = (Notification) -> Void

    private let monitorQueue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private var observer: Observer?

    // Track all sources by file descriptor
    private var readSources: [Int32: DispatchSourceRead] = [:]
    private var writeSources: [Int32: DispatchSourceWrite] = [:]

    // Track read/write status for each file descriptor
    private var fileDescriptorStatus: [Int32: (isReadable: Bool, isWritable: Bool)] = [:]

    // Tell observer when fd becomes readable if read is true or writable if write is true
    func add(fd: Int32, read: Bool, write: Bool) {
        monitorQueue.async { [weak self] in
            guard let self = self else { return }

            // Remove existing sources first to avoid duplicates
            self.removeSourcesForFileDescriptor(fd)

            if read {
                self.addReadSource(for: fd)
            }

            if write {
                self.addWriteSource(for: fd)
            }
        }
    }

    // Never notify observer about fd in the future
    func remove(fd: Int32) {
        monitorQueue.async { [weak self] in
            guard let self = self else { return }
            self.removeSourcesForFileDescriptor(fd)
        }
    }

    // observer will be called on the specified queue when there is an update
    init(queue: DispatchQueue, observer: @escaping Observer) {
        self.callbackQueue = queue
        self.observer = observer
        self.monitorQueue = DispatchQueue(label: "com.fileDescriptorMonitor.queue",
                                         qos: .utility,
                                         attributes: [])
    }

    deinit {
        // Clean up all sources when the monitor is deallocated
        let allFds = Array(readSources.keys) + Array(writeSources.keys)
        for fd in Set(allFds) {
            removeSourcesForFileDescriptor(fd)
        }
    }

    // MARK: - Private Methods

    private func addReadSource(for fd: Int32) {
        NSLog("FileDescriptorMonitor: add read source for \(fd)")
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: monitorQueue)

        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            // Notify observer that this file descriptor is readable
            NSLog("FileDescirptorMonitor: GCD says \(fd) became readable")
            self.notifyObserver(fd: fd, isReadable: true, isWritable: false)
        }

        source.setCancelHandler {
            // Prevent file descriptor from being closed automatically by GCD
            // This allows the client to manage the file descriptor's lifecycle
        }

        // Store the source and resume it
        readSources[fd] = source
        source.resume()
    }

    private func addWriteSource(for fd: Int32) {
        NSLog("FileDescriptorMonitor: add write source for \(fd)")
        let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: monitorQueue)

        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            // Notify observer that this file descriptor is writable
            self.notifyObserver(fd: fd, isReadable: false, isWritable: true)
        }

        source.setCancelHandler {
            // Prevent file descriptor from being closed automatically by GCD
            // This allows the client to manage the file descriptor's lifecycle
        }

        // Store the source and resume it
        writeSources[fd] = source
        source.resume()
    }

    private func removeSourcesForFileDescriptor(_ fd: Int32) {
        NSLog("FileDescriptorMonitor: remove sources for \(fd)")
        // Cancel and remove read source
        if let readSource = readSources[fd] {
            readSource.cancel()
            readSources.removeValue(forKey: fd)
        }

        // Cancel and remove write source
        if let writeSource = writeSources[fd] {
            writeSource.cancel()
            writeSources.removeValue(forKey: fd)
        }
    }

    private func notifyObserver(fd: Int32, isReadable: Bool, isWritable: Bool) {
        // Create a notification for the single file descriptor
        let notification = Notification(
            fileDescriptor: fd,
            isReadable: isReadable,
            isWritable: isWritable
        )

        // Dispatch notification to observer on the callback queue
        callbackQueue.sync { [weak self] in
            guard let self, let observer = self.observer else {
                return
            }
            observer(notification)
        }
    }
}
