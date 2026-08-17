//
//  NSHost+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import "NSHost+iTerm.h"

#import "iTermAdvancedSettingsModel.h"

#import <SystemConfiguration/SystemConfiguration.h>
#include <unistd.h>

// Case-insensitive: does `hostname` exactly equal any of `names`? This is the
// only matching rule (no short-label / domain leniency): a name is this machine
// only if it is literally one of this machine's names. Leniency here would, over
// a plain-ssh transport we can't prove shares our filesystem, misclassify a
// remote reporting `localhost` or a same-short-name peer as local.
static BOOL iTermHostnameExactlyMatchesAny(NSString *hostname, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        if ([hostname caseInsensitiveCompare:name] == NSOrderedSame) {
            return YES;
        }
    }
    return NO;
}

// The primary DNS domain (e.g. "attlocal.net") from the dynamic store, or nil.
// A fast local IPC to configd, no DNS lookup. Used to build the DHCP FQDN so the
// .local-vs-FQDN bridge is symmetric regardless of which form gethostname()
// returns.
static NSString *iTermPrimaryDNSDomainName(void) {
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("com.googlecode.iterm2.localhost"), NULL, NULL);
    if (!store) {
        return nil;
    }
    NSString *result = nil;
    CFPropertyListRef value = SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/DNS"));
    if (value) {
        if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
            id domain = ((__bridge NSDictionary *)value)[@"DomainName"];
            if ([domain isKindOfClass:[NSString class]] && [domain length] > 0) {
                result = domain;
            }
        }
        CFRelease(value);
    }
    CFRelease(store);
    return result;
}

// Lowercased names confirmed to be this machine at some point, beyond the ones
// live right now. It grows as the machine's names drift over time (a name that
// exactly matched the live names when a shell reported it is retained here), so
// an earlier name stays recognized after gethostname() moves on. In-memory for
// the app's lifetime; the live names reseed the effective set each launch.
static NSMutableSet<NSString *> *iTermRememberedLocalNames(void) {
    static NSMutableSet<NSString *> *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSMutableSet set];
    });
    return set;
}

@implementation NSHost(iTerm)

+ (NSString *)fullyQualifiedDomainName {
    // Testing override: pretend the machine has a different hostname so the
    // localhost-detection paths can be exercised without actually renaming the
    // computer. Empty (the default) means use the real hostname.
    NSString *fake = [iTermAdvancedSettingsModel fakeFullyQualifiedDomainName];
    if (fake.length > 0) {
        return fake;
    }
    char buffer[MAXHOSTNAMELEN];
    const int rc = gethostname(buffer, sizeof(buffer));
    NSString *name = nil;
    if (rc == 0) {
        name = [NSString stringWithUTF8String:buffer];
    }
    return name ?: @"localhost";
}

+ (NSArray<NSString *> *)it_localHostNames {
    // The testing override wins outright so localhost-detection tests are
    // deterministic (see fakeFullyQualifiedDomainName).
    NSString *fake = [iTermAdvancedSettingsModel fakeFullyQualifiedDomainName];
    if (fake.length > 0) {
        return @[fake];
    }
    // Enumerate the machine's actual names so the matcher can compare exactly
    // instead of guessing with short-label leniency. All sources are local and
    // non-blocking (gethostname() and the dynamic store; no DNS).
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    // The Unix/kernel hostname, which is what a local shell's `hostname` reports.
    // Often the DHCP-assigned name.
    NSString *unixName = [self fullyQualifiedDomainName];
    if (unixName.length > 0) {
        [names addObject:unixName];
    }
    // The Bonjour LocalHostName (e.g. "MacBook-Pro-3"), which macOS keeps
    // independent of the Unix hostname, plus its .local form. Enumerating both
    // this and the Unix name is what makes detection symmetric: whichever a shell
    // reports, it's here.
    CFStringRef localHostNameRef = SCDynamicStoreCopyLocalHostName(NULL);
    NSString *localHostName = localHostNameRef ? (__bridge_transfer NSString *)localHostNameRef : nil;
    if (localHostName.length > 0) {
        [names addObject:localHostName];
        [names addObject:[localHostName stringByAppendingString:@".local"]];
        // The FQDN under the primary DNS domain, covering a shell that reports
        // `hostname -f` (the DHCP FQDN) when gethostname() returned the bare or
        // .local name.
        NSString *domain = iTermPrimaryDNSDomainName();
        if (domain.length > 0) {
            [names addObject:[NSString stringWithFormat:@"%@.%@", localHostName, domain]];
        }
    }
    return names;
}

+ (BOOL)it_hostnameIsThisMachine:(NSString *)hostname {
    if (hostname.length == 0) {
        return NO;
    }
    // Exactly one of this machine's current names.
    if (iTermHostnameExactlyMatchesAny(hostname, [self it_localHostNames])) {
        return YES;
    }
    // Or a name we confirmed local before but the machine has since drifted away
    // from (also matched exactly).
    NSString *key = hostname.lowercaseString;
    @synchronized (NSHost.class) {
        return [iTermRememberedLocalNames() containsObject:key];
    }
}

+ (void)it_rememberLocalHostname:(NSString *)hostname {
    if (hostname.length == 0) {
        return;
    }
    // Only remember names that exactly match a live name right now. That anchors
    // the set to ground truth (a name enters only while it genuinely is this
    // machine) and keeps it from accumulating foreign names.
    if (!iTermHostnameExactlyMatchesAny(hostname, [self it_localHostNames])) {
        return;
    }
    @synchronized (NSHost.class) {
        [iTermRememberedLocalNames() addObject:hostname.lowercaseString];
    }
}

+ (void)it_addRememberedLocalHostnameForTesting:(NSString *)hostname {
    if (hostname.length == 0) {
        return;
    }
    @synchronized (NSHost.class) {
        [iTermRememberedLocalNames() addObject:hostname.lowercaseString];
    }
}

+ (void)it_resetRememberedLocalHostnamesForTesting {
    @synchronized (NSHost.class) {
        [iTermRememberedLocalNames() removeAllObjects];
    }
}

@end

