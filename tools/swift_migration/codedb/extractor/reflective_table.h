// The calls the code database records in reflective_call: C functions and
// Objective-C selectors that reach code by name. This table is the only list
// of them; `extract_sends --reflective-table` prints it, and
// `codedb.py reflective --list` shows that output.
//
// Each entry names one argument (counted from 0; for a message, the argument
// of that keyword) and what it names:
//   selector          a SEL, or for a key-path form a selector name
//   class             a class, by name
//   protocol          a protocol, by name
//   key               a key-value coding key
//   key-path          a key-value coding key path
//   predicate-format  an NSPredicate format string (key paths inside it)
//   method            a Method obtained from the runtime
//   property          a property (objc_property_t) obtained from the runtime
//   implementation    an IMP or a block that becomes a method's
//                     implementation (it names no selector; the call is
//                     recorded so that the site is read)
// A name with several entries records one row per entry. class_argument, when
// not -1, is an argument naming the class the selector is looked up in; its
// class is resolved when it is written [Name class] or as a class function
// with a literal name. A prefix entry matches every name that starts with it,
// and is used only when no exact entry matches.

#ifndef CODEDB_REFLECTIVE_TABLE_H
#define CODEDB_REFLECTIVE_TABLE_H

struct ReflectiveName {
    const char *name;
    bool message;   // true: a message send of this selector; false: a call of this C function
    bool prefix;    // name is a prefix
    int argument;   // the argument that names something
    const char *names;
    int classArgument;
    const char *comment;
};

static const ReflectiveName kReflectiveNames[] = {
    // C functions that turn a name into a selector, class or protocol.
    {"NSSelectorFromString", false, false, 0, "selector", -1, "selector from a string"},
    {"sel_registerName", false, false, 0, "selector", -1, "selector from a C string (runtime)"},
    {"sel_getUid", false, false, 0, "selector", -1, "selector from a C string (runtime)"},
    {"NSClassFromString", false, false, 0, "class", -1, "class from a string"},
    {"objc_getClass", false, false, 0, "class", -1, "class from a C string (runtime)"},
    {"objc_lookUpClass", false, false, 0, "class", -1, "class from a C string, or nil (runtime)"},
    {"NSProtocolFromString", false, false, 0, "protocol", -1, "protocol from a string"},
    {"objc_getProtocol", false, false, 0, "protocol", -1, "protocol from a C string (runtime)"},
    // C functions that look up, add or replace methods.
    {"class_getInstanceMethod", false, false, 1, "selector", 0, "instance method lookup (runtime)"},
    {"class_getClassMethod", false, false, 1, "selector", 0, "class method lookup (runtime)"},
    {"class_addMethod", false, false, 1, "selector", 0, "adds a method under a selector (runtime)"},
    {"class_replaceMethod", false, false, 1, "selector", 0, "replaces the method of a selector (runtime)"},
    {"method_exchangeImplementations", false, false, 0, "method", -1, "swizzle: the first method"},
    {"method_exchangeImplementations", false, false, 1, "method", -1, "swizzle: the second method"},
    {"method_setImplementation", false, false, 0, "method", -1, "replaces a method's implementation (runtime)"},
    {"method_getImplementation", false, false, 0, "method", -1,
     "IMP of a method, usually kept to call the original after a swizzle (runtime)"},
    {"imp_implementationWithBlock", false, false, 0, "implementation", -1,
     "a block made into an IMP, to be added or set as a method (runtime)"},
    {"class_copyMethodList", false, false, 0, "class", -1,
     "lists a class's methods, reaching them by enumeration, not by name (runtime)"},
    {"method_getName", false, false, 0, "method", -1,
     "selector of a method, usually one listed by class_copyMethodList (runtime)"},
    // C functions that list properties, reaching their accessors by
    // enumeration (key-value coding of the names they return).
    {"class_copyPropertyList", false, false, 0, "class", -1,
     "lists a class's properties, reaching their accessors by enumeration, not by name (runtime)"},
    {"property_getName", false, false, 0, "property", -1,
     "name of a property, usually one listed by class_copyPropertyList (runtime)"},
    {"protocol_getMethodDescription", false, false, 1, "selector", -1, "looks up a protocol's method (runtime)"},
    {"objc_allocateClassPair", false, false, 1, "class", -1, "makes a class at run time, by name (runtime)"},
    {"object_setClass", false, false, 1, "class", -1, "changes an object's class (runtime)"},
    {"objc_msgSend", false, true, 1, "selector", -1,
     "direct call of objc_msgSend or a variant (objc_msgSendSuper, objc_msgSend_stret, ...)"},
    // Sending a selector.
    {"performSelector", true, true, 0, "selector", -1,
     "every performSelector... variant: withObject:, afterDelay:, OnMainThread:, InBackground:, onThread:"},
    {"makeObjectsPerformSelector:", true, false, 0, "selector", -1, "sent to every element of a collection"},
    {"makeObjectsPerformSelector:withObject:", true, false, 0, "selector", -1, "sent to every element of a collection"},
    {"cancelPreviousPerformRequestsWithTarget:selector:object:", true, false, 1, "selector", -1,
     "cancels a delayed performSelector"},
    {"sortedArrayUsingSelector:", true, false, 0, "selector", -1, "comparator sent to every element"},
    {"sortUsingSelector:", true, false, 0, "selector", -1, "comparator sent to every element"},
    {"setSelector:", true, false, 0, "selector", -1, "NSInvocation's selector"},
    // Asking about a selector.
    {"respondsToSelector:", true, false, 0, "selector", -1, "takes another branch when the method is missing"},
    {"instancesRespondToSelector:", true, false, 0, "selector", -1, "class form of respondsToSelector:"},
    {"methodForSelector:", true, false, 0, "selector", -1, "IMP of a selector"},
    {"instanceMethodForSelector:", true, false, 0, "selector", -1, "IMP of a selector, class form"},
    {"methodSignatureForSelector:", true, false, 0, "selector", -1, "forwarding and NSInvocation"},
    {"instanceMethodSignatureForSelector:", true, false, 0, "selector", -1, "class form of the above"},
    {"doesNotRecognizeSelector:", true, false, 0, "selector", -1, "forwarding"},
    // Key-value coding.
    {"valueForKey:", true, false, 0, "key", -1, "key-value coding getter"},
    {"setValue:forKey:", true, false, 1, "key", -1, "key-value coding setter"},
    {"valueForKeyPath:", true, false, 0, "key-path", -1, "key-value coding getter by path"},
    {"setValue:forKeyPath:", true, false, 1, "key-path", -1, "key-value coding setter by path"},
    {"mutableArrayValueForKey:", true, false, 0, "key", -1, "to-many proxy (insertObject:in<Key>AtIndex: and others)"},
    {"mutableArrayValueForKeyPath:", true, false, 0, "key-path", -1, "to-many proxy by path"},
    {"mutableSetValueForKey:", true, false, 0, "key", -1, "to-many proxy"},
    {"mutableSetValueForKeyPath:", true, false, 0, "key-path", -1, "to-many proxy by path"},
    {"mutableOrderedSetValueForKey:", true, false, 0, "key", -1, "to-many proxy"},
    {"mutableOrderedSetValueForKeyPath:", true, false, 0, "key-path", -1, "to-many proxy by path"},
    // Key-value observing.
    {"addObserver:forKeyPath:options:context:", true, false, 1, "key-path", -1, "observes a key path"},
    {"removeObserver:forKeyPath:", true, false, 1, "key-path", -1, "stops observing"},
    {"removeObserver:forKeyPath:context:", true, false, 1, "key-path", -1, "stops observing"},
    {"willChangeValueForKey:", true, false, 0, "key", -1, "manual change notification"},
    {"didChangeValueForKey:", true, false, 0, "key", -1, "manual change notification"},
    {"keyPathsForValuesAffectingValueForKey:", true, false, 0, "key", -1, "dependent keys"},
    // Bindings.
    {"bind:toObject:withKeyPath:options:", true, false, 0, "key", -1, "the binding name, a key of the receiver"},
    {"bind:toObject:withKeyPath:options:", true, false, 2, "key-path", -1, "the observed key path"},
    // Sort descriptors and predicates.
    {"sortDescriptorWithKey:ascending:", true, false, 0, "key-path", -1, "NSSortDescriptor key"},
    {"sortDescriptorWithKey:ascending:selector:", true, false, 0, "key-path", -1, "NSSortDescriptor key"},
    {"sortDescriptorWithKey:ascending:selector:", true, false, 2, "selector", -1, "comparator sent to the values"},
    {"sortDescriptorWithKey:ascending:comparator:", true, false, 0, "key-path", -1, "NSSortDescriptor key"},
    {"initWithKey:ascending:", true, false, 0, "key-path", -1, "NSSortDescriptor key"},
    {"initWithKey:ascending:selector:", true, false, 0, "key-path", -1, "NSSortDescriptor key"},
    {"initWithKey:ascending:selector:", true, false, 2, "selector", -1, "comparator sent to the values"},
    {"initWithKey:ascending:comparator:", true, false, 0, "key-path", -1, "NSSortDescriptor key"},
    {"predicateWithFormat:", true, false, 0, "predicate-format", -1, "NSPredicate format"},
    {"predicateWithFormat:argumentArray:", true, false, 0, "predicate-format", -1, "NSPredicate format"},
    {"predicateWithFormat:arguments:", true, false, 0, "predicate-format", -1, "NSPredicate format"},
    // Target and action.
    {"setAction:", true, false, 0, "selector", -1, "control or menu item action"},
    {"setDoubleAction:", true, false, 0, "selector", -1, "table or browser double-click action"},
    {"initWithTarget:action:", true, false, 1, "selector", -1, "gesture recognizer action"},
    {"initWithTitle:action:keyEquivalent:", true, false, 1, "selector", -1, "NSMenuItem action"},
    {"addItemWithTitle:action:keyEquivalent:", true, false, 1, "selector", -1, "NSMenu item action"},
    {"insertItemWithTitle:action:keyEquivalent:atIndex:", true, false, 1, "selector", -1, "NSMenu item action"},
    {"addTarget:action:", true, false, 1, "selector", -1, "target and action pair"},
    {"sendAction:to:from:", true, false, 0, "selector", -1, "NSApplication action dispatch"},
    {"tryToPerform:with:", true, false, 0, "selector", -1, "responder chain dispatch"},
    {"targetForAction:", true, false, 0, "selector", -1, "responder chain lookup"},
    {"targetForAction:to:from:", true, false, 0, "selector", -1, "responder chain lookup"},
    // Timers, notifications, threads, undo, sheets and Apple events.
    {"scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:", true, false, 2, "selector", -1, "NSTimer"},
    {"timerWithTimeInterval:target:selector:userInfo:repeats:", true, false, 2, "selector", -1, "NSTimer"},
    {"initWithFireDate:interval:target:selector:userInfo:repeats:", true, false, 3, "selector", -1, "NSTimer"},
    {"addObserver:selector:name:object:", true, false, 1, "selector", -1, "notification observer"},
    {"addObserver:selector:name:object:suspensionBehavior:", true, false, 1, "selector", -1,
     "distributed notification observer"},
    {"detachNewThreadSelector:toTarget:withObject:", true, false, 0, "selector", -1, "NSThread"},
    {"initWithTarget:selector:object:", true, false, 1, "selector", -1, "NSThread or NSInvocationOperation"},
    {"registerUndoWithTarget:selector:object:", true, false, 1, "selector", -1, "NSUndoManager"},
    {"beginSheetModalForWindow:modalDelegate:didEndSelector:contextInfo:", true, false, 2, "selector", -1,
     "sheet callback"},
    {"setEventHandler:andSelector:forEventClass:andEventID:", true, false, 1, "selector", -1,
     "NSAppleEventManager handler"},
};

#endif
