//
//  IOBuffer.swift
//  iTerm2
//
//  Created by George Nachman on 4/13/25.
//

import Foundation

@objc(iTermIOBuffer)
class IOBuffer: NSObject {
    // Type definitions for read and write closures
    typealias ReadClosure = () -> ()
    typealias WriteClosure = (Data) -> Int

    // File descriptor this buffer is managing
    private let fileDescriptor: Int32

    // Queue for performing read/write operations
    private let operationQueue: DispatchQueue

    // Closures for actual I/O operations
    private let readClosure: ReadClosure
    private let writeClosure: WriteClosure

    // State tracking
    private var _isValid = true
    var isValid: Bool { return operationQueue.sync { _isValid } }
    private var isMonitoringWrites = false

    // Write buffer queue
    private var writeQueue = [Data]()
    private var fileDescriptorMonitor: FileDescriptorMonitor!

    init(fileDescriptor: Int32,
         operationQueue: DispatchQueue,
         readClosure: @escaping ReadClosure,
         writeClosure: @escaping WriteClosure) {
        self.fileDescriptor = fileDescriptor
        self.operationQueue = operationQueue
        self.readClosure = readClosure
        self.writeClosure = writeClosure

        super.init()

        NSLog("Start IOBuffer for fd \(fileDescriptor)")
        fileDescriptorMonitor = FileDescriptorMonitor(queue: operationQueue) { [weak self] notif in
            self?._handleMonitorNotification(notif)
        }
        startMonitoringReads()
    }

    deinit {
        fileDescriptorMonitor.remove(fd: fileDescriptor)
        let readClosure = self.readClosure
        // Signal EOF to read callback
        operationQueue.async {
            readClosure()
        }
    }

    // MARK: - Public Methods

    @objc
    func write(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        operationQueue.async { [weak self] in
            guard let self, self._isValid else {
                return
            }

            // Add data to write queue
            writeQueue.append(data)

            // Start monitoring for write availability if not already
            if !isMonitoringWrites {
                _startMonitoringWrites()
            }
        }
    }

    @objc
    func invalidate() {
        operationQueue.async { [weak self] in
            self?._invalidate()
        }
    }

    // Runs on operation queue
    private func _invalidate() {
        guard  _isValid else {
            return
        }

        _isValid = false

        // Stop monitoring this file descriptor
        fileDescriptorMonitor.remove(fd: fileDescriptor)

        // Clear write queue
        writeQueue.removeAll()

        // Signal EOF to read callback
        readClosure()
    }

    // MARK: - Private Methods

    private func startMonitoringReads() {
        operationQueue.async { [weak self] in
            self?._startMonitoringReads()
        }
    }

    private func _startMonitoringReads() {
        guard _isValid else {
            return
        }
        NSLog("IOBuffer: Start monitoring reads")
        fileDescriptorMonitor.add(fd: fileDescriptor, read: true, write: isMonitoringWrites)
    }

    private func startMonitoringWrites() {
        operationQueue.async { [weak self] in
            self?._startMonitoringWrites()
        }
    }

    private func _startMonitoringWrites() {
        guard _isValid, !isMonitoringWrites else {
            return
        }

        isMonitoringWrites = true
        fileDescriptorMonitor.add(fd: fileDescriptor, read: true, write: true)
    }

    private func _stopMonitoringWrites() {
        guard _isValid, isMonitoringWrites else {
            return
        }

        isMonitoringWrites = false
        fileDescriptorMonitor.add(fd: fileDescriptor, read: true, write: false)
    }

    private func _handleReadReady() {
        guard _isValid else {
            return
        }

        readClosure()
    }

    private func _handleWriteReady() {
        guard _isValid, !writeQueue.isEmpty else {
            return
        }
        while let dataToWrite = writeQueue.first {
            it_assert(dataToWrite.count > 0, "Empty messages not supported")

            // Perform the write
            let bytesWritten = writeClosure(dataToWrite)

            if bytesWritten == 0 {
                // Can't write? Assume the server is dead.
                _invalidate()
                break
            } else if bytesWritten < dataToWrite.count {
                // Partial write - keep the remaining data but stop trying to write.
                let remainingData = dataToWrite.advanced(by: bytesWritten)
                writeQueue[0] = remainingData
                break
            }

            // Happy path: wrote the whole message. Remove it and try the next one.
            writeQueue.removeFirst()
        }
        _stopMonitoringWrites()
    }

    // MARK: - Static Handler

    func _handleMonitorNotification(_ notification: FileDescriptorMonitor.Notification) {
        NSLog("IOBuffer received notification \(notification)")

        // Dispatch to the appropriate handler methods
        if notification.isReadable {
            _handleReadReady()
        }

        if notification.isWritable {
            _handleWriteReady()
        }
    }
}
