//
//  InstanceCensus.swift
//  ModernTests
//
//  The instance census of docs/swift-migration/lifetimes.md: a count of the
//  live instances of chosen Objective-C classes in the test host. A test
//  starts tracking the classes it cares about, takes a mark, runs a scenario,
//  and checks that no instance allocated since the mark is still alive. A
//  class whose count grows after a port has a leak.
//
//  How it counts. Tracking a class replaces its +allocWithZone: and -dealloc
//  with versions that record the address of every instance allocated from
//  then on and forget it when the instance is deallocated, then call the
//  original implementation. Only instances allocated after tracking began are
//  counted, so an instance that existed before cannot make a count negative.
//  The runtime sends +allocWithZone: for every allocation once a class
//  overrides it, from Objective-C (+alloc, +new, objc_alloc) and from Swift
//  (objc_allocWithZone) alike. Nothing is added to the app, no associated
//  object is used, and the counts cost a lock per allocation and
//  deallocation of a tracked class.
//
//  Marks. Every counted allocation gets a serial number. A mark is the next
//  serial number, so counting "since a mark" sees only what a scenario
//  allocated. Objects left over from other tests, which may be freed in the
//  middle of the scenario (a closed session waits out its undo timeout), then
//  cannot disturb the count.
//
//  Freed without -dealloc. A Swift convenience initializer that delegates
//  to a designated initializer not exposed to Objective-C (TokenExecutor's
//  initWithTerminal:slownessDetector:queue:ownsQueue:, which delegates to
//  init(_:slownessDetector:queue:ownsQueue:permits:)) frees the instance it
//  was given without sending it -dealloc and returns a second instance that
//  it allocated through +allocWithZone: again. This happens for Objective-C
//  and Swift callers alike. So each counted instance also has a weak
//  reference, which the runtime clears however the instance is freed, and
//  the counts include only instances whose weak reference is still set.
//
//  Such an instance leaves a stale record behind, keyed by its address. It
//  cannot be mistaken for a live instance: its weak reference reads nil, so
//  it is never counted, and a later instance allocated at the same address
//  replaces the record, because didAllocate(_:_:) keeps an existing record
//  only while its weak reference still reads the object. A stale record is
//  never freed otherwise, which costs a few dozen bytes per such instance.
//
//  Why not the alternatives. Weak references held by a test find out whether
//  the objects the test made are freed, which is what a witness test needs,
//  but they cannot count instances that something else made (a tab's
//  sessions, a window's views). Enumerating the malloc heap needs no hooks,
//  but the test target runs under the address sanitizer, whose malloc zone
//  does not support enumeration, so it would find nothing.
//
//  Side effects. The replaced methods stay in place for the rest of the test
//  process, because an instance counted by a hook must find the hook when it
//  is freed. A runtime snapshot (RuntimeSnapshot.swift) taken later in the
//  same process would show the replacement implementations, which is one
//  reason runtime_snapshot.sh runs the snapshot alone.
//
//  The census also records on which thread each counted instance was
//  deallocated, so a witness test can assert the thread that
//  docs/swift-migration/concurrency.md section 6 asks it to preserve.
//

import Foundation
import ObjectiveC
@testable import iTerm2SharedARC

final class InstanceCensus {
    static let shared = InstanceCensus()

    /// A point in the sequence of counted allocations.
    struct Mark {
        fileprivate let serial: UInt64
    }

    /// Where counted instances were deallocated.
    struct DeallocThreads: Equatable, CustomStringConvertible {
        var main = 0
        var other = 0

        var description: String {
            return "main=\(main) other=\(other)"
        }
    }

    private final class WeakReference {
        weak var object: AnyObject?

        init(_ object: AnyObject) {
            self.object = object
        }
    }

    private struct LiveInstance {
        var cls: AnyClass
        var serial: UInt64
        // Nil once the instance is freed, even if it was freed without
        // -dealloc. See "Freed without -dealloc" above.
        var reference: WeakReference
    }

    private struct Deallocation {
        var cls: AnyClass
        var serial: UInt64
        var onMainThread: Bool
    }

    private let lock = NSLock()
    // Guarded by lock. Address of a live counted instance to what was recorded at allocation.
    private var live = [UInt: LiveInstance]()
    // Guarded by lock.
    private var tracked = Set<ObjectIdentifier>()
    // Guarded by lock.
    private var nextSerial: UInt64 = 0
    // Guarded by lock. One small record per counted deallocation.
    private var deallocations = [Deallocation]()

    private init() {}

    /// Starts counting instances of each class, allocated from now on. Calling
    /// it again for a class already tracked does nothing. Call on the main
    /// thread, before the instances of interest are allocated.
    func track(_ classes: [AnyClass]) {
        for cls in classes {
            let isNew: Bool = lock.withLock {
                tracked.insert(ObjectIdentifier(cls)).inserted
            }
            if isNew {
                hookDealloc(cls)
                hookAllocWithZone(cls)
            }
        }
    }

    /// Marks the current point, for counting what is allocated after it.
    func mark() -> Mark {
        return lock.withLock {
            Mark(serial: nextSerial)
        }
    }

    /// The number of live counted instances of `cls` or a subclass of it,
    /// allocated since `mark`, or since tracking began if `mark` is nil.
    /// `cls` must be tracked, or be a subclass of a tracked class.
    func count(of cls: AnyClass, since mark: Mark? = nil) -> Int {
        let start = mark?.serial ?? 0
        let candidates: [WeakReference] = lock.withLock {
            it_assert(isTrackedLocked(cls), "\(cls) is not tracked")
            return live.values.filter { $0.serial >= start && $0.cls.isSubclass(of: cls) }.map(\.reference)
        }
        // Read the weak references outside the lock: reading one retains the
        // object for a moment, and if that turns out to be the last reference,
        // releasing it runs -dealloc, whose hook takes the lock.
        return autoreleasepool {
            candidates.filter { $0.object != nil }.count
        }
    }

    /// Live counts of each of `classes` since `mark`, keyed by class name,
    /// leaving out zeros. Empty when everything allocated since the mark is
    /// gone.
    func survivors(of classes: [AnyClass], since mark: Mark) -> [String: Int] {
        var result = [String: Int]()
        for cls in classes {
            let n = count(of: cls, since: mark)
            if n > 0 {
                result[NSStringFromClass(cls)] = n
            }
        }
        return result
    }

    /// The number of counted instances of `cls` or a subclass of it,
    /// allocated since `mark`, that have been deallocated, by thread.
    func deallocThreads(of cls: AnyClass, since mark: Mark) -> DeallocThreads {
        return lock.withLock {
            var result = DeallocThreads()
            for deallocation in deallocations where deallocation.serial >= mark.serial && deallocation.cls.isSubclass(of: cls) {
                if deallocation.onMainThread {
                    result.main += 1
                } else {
                    result.other += 1
                }
            }
            return result
        }
    }

    private func isTrackedLocked(_ cls: AnyClass) -> Bool {
        var current: AnyClass? = cls
        while let candidate = current {
            if tracked.contains(ObjectIdentifier(candidate)) {
                return true
            }
            current = class_getSuperclass(candidate)
        }
        return false
    }

    // MARK: - Recording

    fileprivate func didAllocate(_ object: UnsafeMutableRawPointer, _ cls: AnyClass) {
        let address = UInt(bitPattern: object)
        // A newly allocated object may be retained and released like any other.
        let reference = WeakReference(Unmanaged<AnyObject>.fromOpaque(object).takeUnretainedValue())
        let previous: WeakReference? = lock.withLock {
            live[address]?.reference
        }
        // With a tracked class and a tracked subclass, both hooks run for one
        // instance. An entry whose object is gone is left from an instance
        // freed without -dealloc, and this one replaces it. The weak reference
        // is read outside the lock for the reason given in count(of:since:).
        if let previous, autoreleasepool(invoking: { previous.object != nil }) {
            return
        }
        lock.withLock {
            live[address] = LiveInstance(cls: cls, serial: nextSerial, reference: reference)
            nextSerial += 1
        }
    }

    fileprivate func willDeallocate(_ address: UInt) {
        let onMainThread = Thread.isMainThread
        lock.withLock {
            // With a tracked class and a tracked subclass, both hooks run for one instance.
            guard let instance = live.removeValue(forKey: address) else {
                return
            }
            deallocations.append(Deallocation(cls: instance.cls,
                                              serial: instance.serial,
                                              onMainThread: onMainThread))
        }
    }

    // MARK: - Hooks

    // The hooks take and pass objects as raw pointers so that Swift never
    // retains or releases an object that is being deallocated. Only
    // didAllocate(_:_:) turns one into a reference, to make its weak reference.
    private typealias DeallocFunction = @convention(c) (UnsafeRawPointer, Selector) -> Void
    private typealias DeallocBlock = @convention(block) (UnsafeRawPointer) -> Void
    private typealias AllocFunction = @convention(c) (UnsafeRawPointer, Selector, OpaquePointer?) -> UnsafeMutableRawPointer?
    private typealias AllocBlock = @convention(block) (UnsafeRawPointer, OpaquePointer?) -> UnsafeMutableRawPointer?

    private static func ownMethod(of cls: AnyClass, _ selector: Selector) -> Method? {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            return nil
        }
        defer {
            free(methods)
        }
        for i in 0..<Int(count) where method_getName(methods[i]) == selector {
            return methods[i]
        }
        return nil
    }

    private func hookDealloc(_ cls: AnyClass) {
        let selector = NSSelectorFromString("dealloc")
        if let method = Self.ownMethod(of: cls, selector) {
            let original = unsafeBitCast(method_getImplementation(method), to: DeallocFunction.self)
            let block: DeallocBlock = { object in
                InstanceCensus.shared.willDeallocate(UInt(bitPattern: object))
                original(object, selector)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        } else {
            // The class inherits -dealloc. Add one that forwards to whatever
            // the superclass has when it runs.
            guard let superclass = class_getSuperclass(cls),
                  let inherited = class_getInstanceMethod(superclass, selector) else {
                it_fatalError("\(cls) has no dealloc")
            }
            let block: DeallocBlock = { object in
                InstanceCensus.shared.willDeallocate(UInt(bitPattern: object))
                let imp = class_getMethodImplementation(superclass, selector)
                unsafeBitCast(imp, to: DeallocFunction.self)(object, selector)
            }
            class_addMethod(cls, selector, imp_implementationWithBlock(block), method_getTypeEncoding(inherited))
        }
    }

    private func hookAllocWithZone(_ cls: AnyClass) {
        let selector = NSSelectorFromString("allocWithZone:")
        // Class methods live on the metaclass.
        guard let metaclass = object_getClass(cls) else {
            it_fatalError("\(cls) has no metaclass")
        }
        // The receiver of +allocWithZone: is the class being instantiated,
        // which may be a subclass of `cls`.
        let record: (UnsafeRawPointer, UnsafeMutableRawPointer?) -> Void = { receiver, object in
            guard let object else {
                return
            }
            InstanceCensus.shared.didAllocate(object, unsafeBitCast(receiver, to: AnyClass.self))
        }
        if let method = Self.ownMethod(of: metaclass, selector) {
            let original = unsafeBitCast(method_getImplementation(method), to: AllocFunction.self)
            let block: AllocBlock = { receiver, zone in
                let object = original(receiver, selector, zone)
                record(receiver, object)
                return object
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        } else {
            guard let superMetaclass = class_getSuperclass(metaclass),
                  let inherited = class_getInstanceMethod(superMetaclass, selector) else {
                it_fatalError("\(cls) has no allocWithZone:")
            }
            let block: AllocBlock = { receiver, zone in
                let imp = class_getMethodImplementation(superMetaclass, selector)
                let object = unsafeBitCast(imp, to: AllocFunction.self)(receiver, selector, zone)
                record(receiver, object)
                return object
            }
            class_addMethod(metaclass, selector, imp_implementationWithBlock(block), method_getTypeEncoding(inherited))
        }
    }
}
