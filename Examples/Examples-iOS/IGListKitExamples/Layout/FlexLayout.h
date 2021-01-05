//
//  FlexLayout.h
//  IGListKitExamples
//
//  Created by junlin3 on 2020/12/17.
//  Copyright © 2020 Instagram. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "IGListCollectionViewLayoutCompatible.h"

NS_ASSUME_NONNULL_BEGIN

@interface FlexLayout : UICollectionViewLayout <IGListCollectionViewLayoutCompatible>

@property (nonatomic, readonly) UICollectionViewScrollDirection scrollDirection;

@property (nonatomic, assign) CGFloat stickyHeaderYOffset;

@property (nonatomic, assign) BOOL showHeaderWhenEmpty;

/**
 Create and return a new collection view layout.

 @param stickyHeaders Set to `YES` to stick section headers to the top of the bounds while scrolling.
 @param scrollDirection Direction along which the collection view will be scrollable (if content size exceeds the frame size)
 @param topContentInset The content inset (top or left, depending on scrolling direction) used to offset the sticky headers. Ignored if stickyHeaders is `NO`.
 @param stretchToEdge Specifies whether to stretch width (in vertically scrolling layout) or height (horizontally scrolling) of last item to right/bottom edge when distance from last item to right/bottom edge < epsilon(1)

 @return A new collection view layout.
 */
- (instancetype)initWithStickyHeaders:(BOOL)stickyHeaders
                      scrollDirection:(UICollectionViewScrollDirection)scrollDirection
                      topContentInset:(CGFloat)topContentInset
                        stretchToEdge:(BOOL)stretchToEdge NS_DESIGNATED_INITIALIZER;

/**
 Create and return a new vertically scrolling collection view layout.

 @param stickyHeaders Set to `YES` to stick section headers to the top of the bounds while scrolling.
 @param topContentInset The top content inset used to offset the sticky headers. Ignored if stickyHeaders is `NO`.
 @param stretchToEdge Specifies whether to stretch width of last item to right edge when distance from last item to right edge < epsilon(1)

 @return A new collection view layout.
 */
- (instancetype)initWithStickyHeaders:(BOOL)stickyHeaders
                      topContentInset:(CGFloat)topContentInset
                        stretchToEdge:(BOOL)stretchToEdge;

/**
 :nodoc:
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 :nodoc:
 */
+ (instancetype)new NS_UNAVAILABLE;


@end

NS_ASSUME_NONNULL_END
