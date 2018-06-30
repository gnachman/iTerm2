//
//  iTermStatusBarSetupCollectionViewItem.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermStatusBarSetupCollectionViewItem : NSCollectionViewItem

@property (nonatomic, copy) NSString *detailText;
@property (nonatomic) BOOL hideDetail;

- (void)sizeToFit;

@end
