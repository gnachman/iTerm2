//
//  iTermPreferencesSearchEngineResultsWindowController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/28/19.
//

#import <Cocoa/Cocoa.h>
#import "iTermPreferencesSearch.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermPreferencesSearchEngineResultsWindowControllerDelegate<NSObject>
- (void)preferencesSearchEngineResultsDidSelectDocument:(nullable iTermPreferencesSearchDocument *)document;
- (void)preferencesSearchEngineResultsDidActivateDocument:(iTermPreferencesSearchDocument *)document;
@end

@interface iTermPreferencesSearchEngineResultsWindowController : NSWindowController
@property (nonatomic, copy) NSArray<iTermPreferencesSearchDocument *> *documents;
@property (nonatomic, weak) id<iTermPreferencesSearchEngineResultsWindowControllerDelegate> delegate;
@property (nullable, nonatomic, readonly) iTermPreferencesSearchDocument *selectedDocument;

- (void)moveDown:(nullable id)sender;
- (void)moveUp:(nullable id)sender;
- (void)insertNewline:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
