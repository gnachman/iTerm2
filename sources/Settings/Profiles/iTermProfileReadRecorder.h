//
//  iTermProfileReadRecorder.h
//  iTerm2SharedARC
//
//  A debug-build linter for the colors reload scope. See ProfileReloadScope.swift for the scope
//  table and -[PTYSession setPreferencesFromAddressBookEntry:] for where this is used.
//
//  Wraps a profile and records every key read while the colors section of the full profile reload
//  is not active. A colors-scope key read outside that section is a dependency the colors scope
//  does not know about: skipping the full reload for a change to that key would leave the reader
//  stale. The full reload wraps both the profile being applied and, in its place, the session's
//  live profile, so a reader that goes through self.profile instead of the profile it was handed
//  is caught too.
//
//  Reads through -objectForKey: (which also backs subscripting, KVC, and every
//  iTermProfilePreferences accessor) are recorded. Whole-dictionary operations are not: key and
//  value enumeration, -allKeys and -allValues, equality and hashing, copying, descriptions, and
//  bulk extraction through -getObjects:andKeys:count:. Each of those is forwarded explicitly, so
//  the boundary does not depend on how Foundation implements them. Bulk extraction is how Swift
//  bridges an unfamiliar NSDictionary into a native Dictionary, so a Swift function that takes the
//  profile as a Swift Dictionary reads from its private copy and is invisible to this linter. Keep
//  such calls out of the reload, or audit them by hand.
//
//  This is Objective-C rather than Swift because it subclasses the NSDictionary class cluster and
//  must override -getObjects:andKeys:count:, which Swift cannot see.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermProfileReadRecorder : NSDictionary<NSString *, id>

// Set while the colors section of the reload is running. Reads made then are not recorded.
@property (nonatomic) BOOL inColorsSection;

// The colors-scope keys read while inColorsSection was NO.
@property (nonatomic, readonly) NSSet<NSString *> *colorsScopeKeysReadOutsideColorsSection;

// A symbolicated backtrace of the first read of a colors-scope key outside the colors section,
// so the assertion can say where the offending reader is. Debug-only, captured at most once.
@property (nonatomic, readonly, nullable) NSArray<NSString *> *firstLeakBacktrace;

- (instancetype)initWithProfile:(NSDictionary *)profile;

@end

NS_ASSUME_NONNULL_END
