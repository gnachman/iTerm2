//
//  SSKeychain.m
//  SSKeychain
//
//  Created by Sam Soffes on 5/19/10.
//  Copyright (c) 2010-2014 Sam Soffes. All rights reserved.
//

#import "SSKeychain.h"

NSString *const kSSKeychainErrorDomain = @"com.samsoffes.sskeychain";
NSString *const kSSKeychainAccountKey = @"acct";
NSString *const kSSKeychainCreatedAtKey = @"cdat";
NSString *const kSSKeychainClassKey = @"labl";
NSString *const kSSKeychainDescriptionKey = @"desc";
NSString *const kSSKeychainLabelKey = @"labl";
NSString *const kSSKeychainLastModifiedKey = @"mdat";
NSString *const kSSKeychainWhereKey = @"svce";

static CFTypeRef SSKeychainAccessibilityType = NULL;
static BOOL SSKeychainSynchronized = NO;

@implementation SSKeychain

+ (void)setSynchronized:(BOOL)synchronized {
    SSKeychainSynchronized = synchronized;
}

+ (BOOL)synchronized {
    return SSKeychainSynchronized;
}

+ (NSString *)passwordForService:(NSString *)serviceName account:(NSString *)account error:(NSError *__autoreleasing *)error {
    return [self passwordForService:serviceName account:account label:nil error:error];
}

+ (NSString *)passwordForService:(NSString *)serviceName
                         account:(NSString *)account
                           label:(NSString *)label
                           error:(NSError *__autoreleasing *)error {
    SSKeychainQuery *query = [[SSKeychainQuery alloc] init];
    if (label) {
        query.label = label;
    }
    query.service = serviceName;
    query.account = account;
    [self updateQuery:query];
    [query fetch:error];
    return query.password;
}


+ (BOOL)deletePasswordForService:(NSString *)serviceName account:(NSString *)account {
    return [self deletePasswordForService:serviceName account:account error:nil];
}


+ (BOOL)deletePasswordForService:(NSString *)serviceName account:(NSString *)account error:(NSError *__autoreleasing *)error {
    return [self deletePasswordForService:serviceName account:account label:nil error:error];
}

+ (BOOL)deletePasswordForService:(NSString *)serviceName account:(NSString *)account label:(NSString *)label error:(NSError *__autoreleasing *)error {
    SSKeychainQuery *query = [[SSKeychainQuery alloc] init];
    if (label) {
        query.label = label;
    }
    query.service = serviceName;
    query.account = account;
    [self updateQuery:query];
    return [query deleteItem:error];
}


+ (BOOL)setPassword:(NSString *)password forService:(NSString *)serviceName account:(NSString *)account {
    return [self setPassword:password forService:serviceName account:account error:nil];
}


+ (BOOL)setPassword:(NSString *)password forService:(NSString *)serviceName account:(NSString *)account error:(NSError *__autoreleasing *)error {
    return [self setPassword:password forService:serviceName account:account label:nil error:error];
}

+ (BOOL)setPassword:(NSString *)password forService:(NSString *)serviceName account:(NSString *)account label:(NSString *)label error:(NSError *__autoreleasing *)error {
    SSKeychainQuery *query = [[SSKeychainQuery alloc] init];
    if (label) {
        query.label = label;
    }
    query.service = serviceName;
    query.account = account;
    query.password = password;
    [self updateQuery:query];
    return [query save:error];
}


+ (NSArray *)allAccounts {
    return [self accountsForService:nil];
}


+ (NSArray *)accountsForService:(NSString *)serviceName {
    SSKeychainQuery *query = [[SSKeychainQuery alloc] init];
    query.service = serviceName;
    [self updateQuery:query];
    return [query fetchAll:nil];
}


+ (CFTypeRef)accessibilityType {
    return SSKeychainAccessibilityType;
}


+ (void)setAccessibilityType:(CFTypeRef)accessibilityType {
    CFRetain(accessibilityType);
    if (SSKeychainAccessibilityType) {
        CFRelease(SSKeychainAccessibilityType);
    }
    SSKeychainAccessibilityType = accessibilityType;
}

+ (void)updateQuery:(SSKeychainQuery *)query {
    if (self.synchronized) {
        query.synchronizationMode = SSKeychainQuerySynchronizationModeYes;
        return;
    }
}

@end
