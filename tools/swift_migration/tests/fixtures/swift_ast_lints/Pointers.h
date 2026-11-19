// Unannotated C and Objective-C declarations for Pointers.swift
// (tools/swift_migration/tests/test_swift_ast_lints.py).
#import <Foundation/Foundation.h>
void FixTakesIntPointer(int *p);
void FixTakesCString(const char *s);
void FixTakesVoidPointer(void *p);
@interface FixLegacy : NSObject
- (void)stash:(NSError **)error;
@end
