//
//  iTermFunctionCallTextFieldDelegate.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/19/18.
//

#import "iTermFunctionCallTextFieldDelegate.h"

#import "iTermAPIHelper.h"
#import "iTermFunctionCallSuggester.h"
#import "iTermVariables.h"
#import "NSArray+iTerm.h"

@interface iTermFunctionCallTextFieldDelegate()<
    NSControlTextEditingDelegate>

@property (nonatomic) BOOL isAutocompleting;
@property (nonatomic, strong) NSString *lastEntry;
@property (nonatomic) BOOL backspaceKey;

@end

@implementation iTermFunctionCallTextFieldDelegate {
    iTermFunctionCallSuggester *_suggester;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSDictionary<NSString *,NSArray<NSString *> *> *signatures =
            [[iTermAPIHelper sharedInstance] registeredFunctionSignatureDictionary];
        NSArray<NSString *> *paths = iTermVariablesGetAll();
        _suggester = [[iTermFunctionCallSuggester alloc] initWithFunctionSignatures:signatures
                                                                              paths:paths];
    }
    return self;
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
}

- (NSArray *)control:(NSControl *)control
            textView:(NSTextView *)textView
         completions:(NSArray *)words
 forPartialWordRange:(NSRange)charRange
 indexOfSelectedItem:(NSInteger *)index {
    if (!self.lastEntry) {
        return nil;
    }
    if (NSMaxRange(charRange) != self.lastEntry.length) {
        // Can't deal with suggestions in the middle!
        return nil;
    }
    NSArray<NSString *> *suggestions = [_suggester suggestionsForString:self.lastEntry];

    if (!suggestions.count) {
        return nil;
    }

    return [suggestions mapWithBlock:^id(NSString *s) {
        return [s substringFromIndex:charRange.location];
    }];

}

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector{
    if (commandSelector == @selector(deleteBackward:)) {
        self.backspaceKey = YES;
    }

    return NO;
}

@end

