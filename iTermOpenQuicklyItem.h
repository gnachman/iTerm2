#import <Foundation/Foundation.h>

@class iTermLogoGenerator;
@class iTermOpenQuicklyTableCellView;

// Represents and item in the Open Quicky table.
@interface iTermOpenQuicklyItem : NSObject

// Globally unique session ID
@property(nonatomic, copy) NSString *sessionId;

// Title for table view (in large text)
@property(nonatomic, copy) NSAttributedString *title;

// Detail text for table view (in small text below title)
@property(nonatomic, retain) NSAttributedString *detail;

// How well this item matches the query. Just a non-negative number. Higher
// scores are better matches.
@property(nonatomic, assign) double score;

// The view. We have to hold on to this to change the text color for
// non-highlighted items. This is hacky :(
@property(nonatomic, retain) iTermOpenQuicklyTableCellView *view;

// Holds the session's colors and can create a logo with them as needed.
@property(nonatomic, retain) iTermLogoGenerator *logoGenerator;

@end
