//
//  NSHost+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSHost(iTerm)

// For localhost. It's too hard to do this as an instance method, and I don't need to get fancy.
+ (NSString *)fullyQualifiedDomainName;

// This machine's actual hostnames: the Unix name (gethostname()), the Bonjour
// LocalHostName and its .local form, and the FQDN under the primary DNS domain.
// Cheap and non-blocking (no DNS). Honors the fakeFullyQualifiedDomainName
// testing override: when set, that is the only local name.
+ (NSArray<NSString *> *)it_localHostNames;

// YES if `hostname` is exactly (case-insensitively) one of this machine's names,
// or a name previously remembered via it_rememberLocalHostname: (so a name the
// machine has since renamed away from stays recognized). Matching is exact only:
// there is deliberately no short-label or bare-"localhost" leniency, so a remote
// reached over plain ssh that reports "localhost", "localhost.localdomain", or a
// name that merely shares this machine's first DNS label is not mistaken for us.
+ (BOOL)it_hostnameIsThisMachine:(nullable NSString *)hostname;

// Record `hostname` as a name for this machine so it's still recognized after
// the live names drift (e.g. an mDNS renumber). A no-op unless the name matches
// the live names right now, which keeps the remembered set anchored to ground
// truth. Call it when a shell reports a host that was judged local.
+ (void)it_rememberLocalHostname:(nullable NSString *)hostname;

// For tests: seed/clear the remembered-local-names set directly.
+ (void)it_addRememberedLocalHostnameForTesting:(NSString *)hostname;
+ (void)it_resetRememberedLocalHostnamesForTesting;

@end

NS_ASSUME_NONNULL_END
