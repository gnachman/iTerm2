//
//  iTermFunctionCallTextFieldDelegate.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/19/18.
//

#import "iTermFunctionCallTextFieldDelegate.h"

#import "iTermAPIHelper.h"
#import "iTermBuiltInFunctions.h"
#import "iTermFunctionCallSuggester.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "iTermVariables.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"
#import "iTermExpressionParser.h"

@interface iTermFunctionCallTextFieldDelegate()<
    NSControlTextEditingDelegate>

@property (nonatomic) BOOL isAutocompleting;
@property (nonatomic, strong) NSString *lastEntry;
@property (nonatomic) BOOL backspaceKey;

@end

@implementation iTermFunctionCallTextFieldDelegate {
    iTermFunctionCallSuggester *_suggester;
    NSSet<NSString *> *(^_pathSource)(NSString *prefix);
}

- (instancetype)initWithPathSource:(NSSet<NSString *> *(^)(NSString *))pathSource
                  passthrough:(id)passthrough
                functionsOnly:(BOOL)functionsOnly {
    self = [super init];
    if (self) {
        NSDictionary<NSString *,NSArray<NSString *> *> *registeredSignatures =
            [iTermAPIHelper registeredFunctionSignatureDictionary];
        NSDictionary<NSString *,NSArray<NSString *> *> *bifSignatures =
            [[iTermBuiltInFunctions sharedInstance] registeredFunctionSignatureDictionary];
        NSDictionary<NSString *,NSArray<NSString *> *> *combinedSignatures = [registeredSignatures dictionaryByMergingDictionary:bifSignatures];
        Class suggesterClass = functionsOnly ? [iTermFunctionCallSuggester class] : [iTermSwiftyStringSuggester class];
        _suggester = [[suggesterClass alloc] initWithFunctionSignatures:combinedSignatures
                                                             pathSource:pathSource];
        _passthrough = passthrough;
        _pathSource = pathSource;
    }
    return self;
}

- (BOOL)smellsLikeSessionContext:(NSString *)string {
    iTermVariableRecordingScope *scope = [[iTermVariableRecordingScope alloc] initWithScope:[[iTermVariableScope alloc] init]];
    iTermParsedExpression *expression = [iTermExpressionParser parsedExpressionWithInterpolatedString:string scope:scope];
    if (!expression) {
        return NO;
    }
    NSSet<NSString *> *(^sessionPathSource)(NSString *) = [iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession];
    for (iTermVariableReference *ref in scope.recordedReferences) {
        if ([ref.path containsString:@"."]) {
            continue;
        }
        if (![_pathSource(ref.path) containsObject:ref.path] &&
            [sessionPathSource(ref.path) containsObject:ref.path]) {
            return YES;
        }
    }
    return NO;
}

- (void)controlTextDidChange:(NSNotification *)obj {
    NSTextView *fieldEditor =  obj.userInfo[@"NSFieldEditor"];

    if (self.isAutocompleting == NO  && !self.backspaceKey) {
        self.isAutocompleting = YES;
        self.lastEntry = [[fieldEditor string] copy];
        [fieldEditor complete:nil];
        self.isAutocompleting = NO;
    }

    self.backspaceKey = NO;
    if ([_passthrough respondsToSelector:_cmd]) {
        [_passthrough controlTextDidChange:obj];
    }

    if (self.canWarnAboutContextMistake &&
        self.contextMistakeText &&
        [self smellsLikeSessionContext:[fieldEditor string]]) {
        [(NSView *)obj.object it_showWarning:self.contextMistakeText];
        self.canWarnAboutContextMistake = NO;
    }
}

- (NSArray *)control:(NSControl *)control
            textView:(NSTextView *)textView
         completions:(NSArray *)words  // Dictionary words
 forPartialWordRange:(NSRange)charRange
 indexOfSelectedItem:(NSInteger *)index {
    NSArray<NSString *> *suggestions = [self suggestionsForRange:charRange];
    *index = -1;  // Don't select anything. Doing so causes pathological behavior when you press period.
    return suggestions;
}

- (NSArray<NSString *> *)suggestionsForRange:(NSRange)charRange {
    if (!self.lastEntry) {
        return nil;
    }
    if (NSMaxRange(charRange) != self.lastEntry.length) {
        // Can't deal with suggestions in the middle!
        return nil;
    }
    NSArray<NSString *> *suggestions = [_suggester suggestionsForString:[self.lastEntry substringToIndex:NSMaxRange(charRange)]];

    if (!suggestions.count) {
        return nil;
    }

    suggestions = [suggestions mapWithBlock:^id(NSString *s) {
        return [s substringFromIndex:charRange.location];
    }];

    suggestions = [suggestions sortedArrayUsingSelector:@selector(compare:)];
    suggestions = [suggestions uniq];
    if (suggestions.count == 0) {
        return nil;
    }

    return suggestions;
}

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(capitalizeWord:) ||
        commandSelector == @selector(changeCaseOfLetter:) ||
        commandSelector == @selector(deleteBackward:) ||
        commandSelector == @selector(deleteBackwardByDecomposingPreviousCharacter:) ||
        commandSelector == @selector(deleteForward:) ||
        commandSelector == @selector(deleteToBeginningOfLine:) ||
        commandSelector == @selector(deleteToBeginningOfParagraph:) ||
        commandSelector == @selector(deleteToEndOfLine:) ||
        commandSelector == @selector(deleteToEndOfParagraph:) ||
        commandSelector == @selector(deleteToMark:) ||
        commandSelector == @selector(deleteWordBackward:) ||
        commandSelector == @selector(deleteWordForward:) ||
        commandSelector == @selector(indent:) ||
        commandSelector == @selector(insertBacktab:) ||
        commandSelector == @selector(insertContainerBreak:) ||
        commandSelector == @selector(insertDoubleQuoteIgnoringSubstitution:) ||
        commandSelector == @selector(insertLineBreak:) ||
        commandSelector == @selector(insertNewline:) ||
        commandSelector == @selector(insertNewlineIgnoringFieldEditor:) ||
        commandSelector == @selector(insertParagraphSeparator:) ||
        commandSelector == @selector(insertSingleQuoteIgnoringSubstitution:) ||
        commandSelector == @selector(insertTab:) ||
        commandSelector == @selector(insertTabIgnoringFieldEditor:) ||
        commandSelector == @selector(lowercaseWord:) ||
        commandSelector == @selector(makeBaseWritingDirectionLeftToRight:) ||
        commandSelector == @selector(makeBaseWritingDirectionNatural:) ||
        commandSelector == @selector(makeBaseWritingDirectionRightToLeft:) ||
        commandSelector == @selector(makeTextWritingDirectionLeftToRight:) ||
        commandSelector == @selector(makeTextWritingDirectionNatural:) ||
        commandSelector == @selector(makeTextWritingDirectionRightToLeft:) ||
        commandSelector == @selector(transpose:) ||
        commandSelector == @selector(transposeWords:) ||
        commandSelector == @selector(uppercaseWord:) ||
        commandSelector == @selector(yank:)) {
        self.backspaceKey = YES;
    }

    return NO;
}

- (void)focusReportingTextFieldWillBecomeFirstResponder:(iTermFocusReportingTextField *)sender {
    NSTextView *fieldEditor = [NSTextView castFrom:[[sender window] fieldEditor:YES forObject:sender]];
    if (self.isAutocompleting == NO  && !self.backspaceKey) {
        self.isAutocompleting = YES;
        self.lastEntry = [[fieldEditor string] copy];
        [fieldEditor complete:nil];
        self.isAutocompleting = NO;
    }

    self.backspaceKey = NO;
    if ([_passthrough respondsToSelector:_cmd]) {
        [_passthrough focusReportingTextFieldWillBecomeFirstResponder:sender];
    }
}

- (void)controlTextDidBeginEditing:(NSNotification *)obj {
    if ([_passthrough respondsToSelector:_cmd]) {
        [_passthrough controlTextDidBeginEditing:obj];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if ([_passthrough respondsToSelector:_cmd]) {
        [_passthrough controlTextDidEndEditing:obj];
    }
    self.canWarnAboutContextMistake = YES;
}

@end

