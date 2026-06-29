//
//  iTermRecordedVariable.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import <Foundation/Foundation.h>
#import "iTermVariables.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermRecordedVariable : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) BOOL isTerminal;
@property (nonatomic, readonly) iTermVariablesSuggestionContext nonterminalContext;

- (instancetype)initTerminalWithName:(NSString *)name;
- (instancetype)initNonterminalWithName:(NSString *)name context:(iTermVariablesSuggestionContext)context;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (instancetype)recordByPrependingPath:(NSString *)path;

- (NSDictionary *)dictionaryValue;

@end

NS_ASSUME_NONNULL_END
