//
//  iTermVariables.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermVariableKeyApplicationPID;
extern NSString *const iTermVariableKeySessionAutoLogID;
extern NSString *const iTermVariableKeySessionColumns;
extern NSString *const iTermVariableKeySessionCreationTimeString;
extern NSString *const iTermVariableKeySessionHostname;
extern NSString *const iTermVariableKeySessionID;
extern NSString *const iTermVariableKeySessionLastCommand;
extern NSString *const iTermVariableKeySessionPath;
extern NSString *const iTermVariableKeySessionName;
extern NSString *const iTermVariableKeySessionRows;
extern NSString *const iTermVariableKeySessionTTY;
extern NSString *const iTermVariableKeySessionUsername;
extern NSString *const iTermVariableKeyTermID;

extern NSString *const iTermVariableKeySessionProfileName;
extern NSString *const iTermVariableKeySessionIconName;
extern NSString *const iTermVariableKeySessionWindowName;
extern NSString *const iTermVariableKeySessionJob;

// Returns an array of all known variables.
NSArray<NSString *> *iTermVariablesGetAll(void);

@class iTermVariables;

@protocol iTermVariablesDelegate<NSObject>
- (void)variables:(iTermVariables *)variables didChangeValuesForNames:(NSSet<NSString *> *)changedNames group:(dispatch_group_t)group;
@end

// Usage:
// iTermVariables *child = [[iTermVariables alloc] init];
// [child setValuesFromDictionary:dict];
// child.delegate = self;
// [parent setValue:child forVariableNamed:@"child name"];
@interface iTermVariables : NSObject

@property (nonatomic, weak) id<iTermVariablesDelegate> delegate;
// TODO: Deprecate this and update the callsites to use evaluation properly
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *legacyDictionary;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *legacyDictionaryExcludingGlobals;
@property (nonatomic, readonly) id (^functionCallSource)(NSString *);

+ (instancetype)globalInstance;

// nil or NSNull value means unset it.
- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name;

// Values of NSNull get unset
- (BOOL)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dict;
- (id)valueForVariableName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
