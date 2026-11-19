// Unannotated Objective-C declarations for IUO.swift
// (tools/swift_migration/tests/test_swift_ast_lints.py).
#import <Foundation/Foundation.h>
@interface FixOld : NSObject
@property (nonatomic, strong) NSString *name;
- (NSString *)describe:(NSString *)x;
+ (FixOld *)shared;
- (NSArray<NSString *> *)items;
@end
NSString *FixOldFunction(void);
