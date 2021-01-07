//
//  WBCollectionViewFlowLayout.m
//  IGListKitExamples
//
//  Created by junlin3 on 2020/12/17.
//  Copyright © 2020 Instagram. All rights reserved.
//

#import "WBCollectionViewFlowLayout.h"
#import "WBCollectionViewDelegateFlowLayout.h"

#import <vector>

#import <IGListDiffKit/IGListAssert.h>
#import <IGListKit/IGListCollectionViewDelegateLayout.h>


@interface UIScrollView (IGListKit)

- (UIEdgeInsets) ig_contentInset;

@end

@implementation UIScrollView (IGListKit)

- (UIEdgeInsets) ig_contentInset
{
    if (@available(iOS 11.0, tvOS 11.0, *)) {
        return self.adjustedContentInset;
    } else {
        return self.contentInset;
    }
}

@end


static CGRect IGListRectIntegralScaled(CGRect rect) {
    CGFloat scale = [[UIScreen mainScreen] scale];
    return CGRectMake(floorf(rect.origin.x * scale) / scale,
                      floorf(rect.origin.y * scale) / scale,
                      ceilf(rect.size.width * scale) / scale,
                      ceilf(rect.size.height * scale) / scale);
}

static CGFloat UIEdgeInsetsLeadingInsetInDirection(UIEdgeInsets insets, UICollectionViewScrollDirection direction) {
    switch (direction) {
        case UICollectionViewScrollDirectionVertical: return insets.top;
        case UICollectionViewScrollDirectionHorizontal: return insets.left;
    }
}

static CGFloat UIEdgeInsetsTrailingInsetInDirection(UIEdgeInsets insets, UICollectionViewScrollDirection direction) {
    switch (direction) {
        case UICollectionViewScrollDirectionVertical: return insets.bottom;
        case UICollectionViewScrollDirectionHorizontal: return insets.right;
    }
}

static CGFloat CGPointGetCoordinateInDirection(CGPoint point, UICollectionViewScrollDirection direction) {
    switch (direction) {
        case UICollectionViewScrollDirectionVertical: return point.y;
        case UICollectionViewScrollDirectionHorizontal: return point.x;
    }
}

static CGFloat CGRectGetLengthInDirection(CGRect rect, UICollectionViewScrollDirection direction) {
    switch (direction) {
        case UICollectionViewScrollDirectionVertical: return rect.size.height;
        case UICollectionViewScrollDirectionHorizontal: return rect.size.width;
    }
}

static CGFloat CGRectGetMaxInDirection(CGRect rect, UICollectionViewScrollDirection direction) {
    switch (direction) {
        case UICollectionViewScrollDirectionVertical: return CGRectGetMaxY(rect);
        case UICollectionViewScrollDirectionHorizontal: return CGRectGetMaxX(rect);
    }
}

static CGFloat CGRectGetMinInDirection(CGRect rect, UICollectionViewScrollDirection direction) {
    switch (direction) {
        case UICollectionViewScrollDirectionVertical: return CGRectGetMinY(rect);
        case UICollectionViewScrollDirectionHorizontal: return CGRectGetMinX(rect);
    }
}

static CGFloat CGSizeGetLengthInDirection(CGSize size, UICollectionViewScrollDirection direction) {
    switch (direction) {
        case UICollectionViewScrollDirectionVertical: return size.height;
        case UICollectionViewScrollDirectionHorizontal: return size.width;
    }
}

static CGFloat CGSizeGetColumnLenInDirection(CGSize size, NSInteger column, CGFloat itemSpacing, UICollectionViewScrollDirection direction)
{
    CGFloat len = 0;
    switch (direction) {
        case UICollectionViewScrollDirectionVertical: len = size.height;
        case UICollectionViewScrollDirectionHorizontal: len = size.width;
    }
    if (column > 1) {
        len = (len - itemSpacing * (column - 1)) / column;
    }
    return len;
}

static NSIndexPath *indexPathForSection(NSInteger section) {
    return [NSIndexPath indexPathForItem:0 inSection:section];
}

static NSInteger IGListMergeMinimumInvalidatedSection(NSInteger section, NSInteger otherSection) {
    if (section == NSNotFound && otherSection == NSNotFound) {
        return NSNotFound;
    } else if (section == NSNotFound) {
        return otherSection;
    } else if (otherSection == NSNotFound) {
        return section;
    }

    return MIN(section, otherSection);
}

struct IGListSectionColumnEntry {
    // 当前列的x坐标（每一列的x坐标在当前组确定列数的时候就确定了）
    CGFloat coordInFixedDirection;
    // 当前列的最边界坐标
    CGFloat lastCoordInScrollDirection;
    
    bool operator< (const IGListSectionColumnEntry entry)const {
        return lastCoordInScrollDirection < entry.lastCoordInScrollDirection;
    }
    bool operator> (const IGListSectionColumnEntry entry)const {
        return lastCoordInScrollDirection > entry.lastCoordInScrollDirection;
    }
};

static bool sortColumnEntry(const IGListSectionColumnEntry& entry1, const IGListSectionColumnEntry& entry2) {
    return entry1.lastCoordInScrollDirection < entry2.lastCoordInScrollDirection;
}

static IGListSectionColumnEntry& largestEntry(std::vector<IGListSectionColumnEntry>& entries) {
    auto *largestEntry = &entries[0];
    for (auto& entry : entries)
    {
        if (*largestEntry > entry) {
            largestEntry = &entry;
        }
    }
    return *largestEntry;
}

static IGListSectionColumnEntry& leastEntry(std::vector<IGListSectionColumnEntry>& entries) {
    auto *leastEntry = &entries[0];
    for (auto& entry : entries)
    {
        if (*leastEntry > entry) {
            leastEntry = &entry;
        }
    }
    return *leastEntry;
}


struct IGListSectionEntry {
    /**
     Represents the minimum-bounding box of every element in the section. This includes all item frames as well as the
     header bounds. It is made simply by unioning all item and header frames. Use this to find section intersections
     to build layout attributes given a rect.
     */
    CGRect bounds;

    // The insets for the section. Used to find total content size of the section.
    UIEdgeInsets insets;

    // The RESTING frame of the header view (e.g. when the header is not sticking to the top of the scroll view).
    CGRect headerBounds;

    // The RESTING frame of the footer view
    CGRect footerBounds;

    // An array of frames for each cell in the section.
    std::vector<CGRect> itemBounds;
    
    // last item distance in scroll direction, used for partial invalidation
    CGFloat lastItemCoordInScrollDirection;

    // last item distance in fixed direction, used for partial invalidation
    CGFloat lastItemCoordInFixedDirection;

    // last next row distance in scroll direction, used for partial invalidation
    CGFloat lastNextRowCoordInScrollDirection;

    /******************************支持waterflow方式的布局*********************************/
    BOOL isWaterflow;
    
    // 当前section支持的列数
    NSInteger columnCount;
    
    // 多列的话，存储列宽，下一列item的起始位置（竖向的话，影响x，横向影响y）
    CGFloat columnWidth;
    
    // 记录每一列排布的最后边界值，找最下的那个放置下一个元素
    std::vector<IGListSectionColumnEntry> columnData;
    
    // 记录下一个添加元素的列下标
    NSInteger nextColumnIndex;
    
    // Returns YES when the section has visible content (header and/or items).
    BOOL isValid() {
        return !CGSizeEqualToSize(bounds.size, CGSizeZero);
    }
};

// Each section has a base zIndex of section * maxZIndexPerSection;
// section header adds (maxZIndexPerSection - 1) to the base zIndex;
// other cells adds (item) to the base zIndex.
// This allows us to present tooltips that can grow from the cell to its top.
static void adjustZIndexForAttributes(UICollectionViewLayoutAttributes *attributes) {
    const NSInteger maxZIndexPerSection = 1000;
    const NSInteger baseZIndex = attributes.indexPath.section * maxZIndexPerSection;

    switch (attributes.representedElementCategory) {
        case UICollectionElementCategoryCell:
            attributes.zIndex = baseZIndex + attributes.indexPath.item;
            break;
        case UICollectionElementCategorySupplementaryView:
            attributes.zIndex = baseZIndex + maxZIndexPerSection - 1;
            break;
        case UICollectionElementCategoryDecorationView:
            attributes.zIndex = baseZIndex - 1;
            break;
    }
}

@interface IGListCollectionViewLayoutInvalidationContext : UICollectionViewLayoutInvalidationContext
@property (nonatomic, assign) BOOL ig_invalidateSupplementaryAttributes;
@property (nonatomic, assign) BOOL ig_invalidateAllAttributes;
@end

@implementation IGListCollectionViewLayoutInvalidationContext
@end




@interface WBCollectionViewFlowLayout ()

@property (nonatomic, assign, readonly) BOOL stickyHeaders;
@property (nonatomic, assign, readonly) CGFloat topContentInset;
@property (nonatomic, assign, readonly) BOOL stretchToEdge;

@end

@implementation WBCollectionViewFlowLayout {
    std::vector<IGListSectionEntry> _sectionData;
    NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *_attributesCache;

    // invalidate starting at this section
    NSInteger _minimumInvalidatedSection;

    /**
     The workflow for getting sticky headers working:
     1. Use a custom invalidation context to mark supplementary attributes invalid.
     2. Return YES from -shouldInvalidateLayoutForBoundsChange:
     3. In -invalidationContextForBoundsChange: mark supplementary attributes invalid on the custom context.
     4. Purge supplementary caches in -invalidateLayoutWithContext: if context says they are invalid
     5. Use cached attributes in -layoutAttributesForSupplementaryViewOfKind:atIndexPath: if they exist, else rebuild
     6. Make sure -layoutAttributesForElementsInRect: always uses the attributes returned from
     -layoutAttributesForSupplementaryViewOfKind:atIndexPath:.
     */
    NSMutableDictionary<NSString *, NSMutableDictionary <NSIndexPath *, UICollectionViewLayoutAttributes *> *> *_supplementaryAttributesCache;
}

- (instancetype)initWithStickyHeaders:(BOOL)stickyHeaders
                      topContentInset:(CGFloat)topContentInset
                        stretchToEdge:(BOOL)stretchToEdge {
    return [self initWithStickyHeaders:stickyHeaders
                       scrollDirection:UICollectionViewScrollDirectionVertical
                       topContentInset:topContentInset
                         stretchToEdge:stretchToEdge];
}

- (instancetype)initWithStickyHeaders:(BOOL)stickyHeaders
                      scrollDirection:(UICollectionViewScrollDirection)scrollDirection
                      topContentInset:(CGFloat)topContentInset
                        stretchToEdge:(BOOL)stretchToEdge {
    if (self = [super init]) {
        _scrollDirection = scrollDirection;
        _stickyHeaders = stickyHeaders;
        _topContentInset = topContentInset;
        _stretchToEdge = stretchToEdge;
        _attributesCache = [NSMutableDictionary new];
        _supplementaryAttributesCache = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                        UICollectionElementKindSectionHeader: [NSMutableDictionary new],
                                                                                        UICollectionElementKindSectionFooter: [NSMutableDictionary new],
                                                                                        }];
        _minimumInvalidatedSection = NSNotFound;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    return [self initWithStickyHeaders:NO topContentInset:0 stretchToEdge:NO];
}

#pragma mark - UICollectionViewLayout

- (UICollectionViewLayoutAttributes *)initialLayoutAttributesForAppearingItemAtIndexPath:(NSIndexPath *)itemIndexPath {
    UICollectionViewLayoutAttributes *attributes = [super initialLayoutAttributesForAppearingItemAtIndexPath:itemIndexPath];
    id<IGListCollectionViewDelegateLayout> delegate = (id<IGListCollectionViewDelegateLayout>)self.collectionView.delegate;
    if ([delegate respondsToSelector:@selector(collectionView:layout:customizedInitialLayoutAttributes:atIndexPath:)]) {
        return [delegate collectionView:self.collectionView
                                 layout:self
      customizedInitialLayoutAttributes:attributes
                            atIndexPath:itemIndexPath];
    }
    return attributes;
}

- (UICollectionViewLayoutAttributes *)finalLayoutAttributesForDisappearingItemAtIndexPath:(NSIndexPath *)itemIndexPath{
    UICollectionViewLayoutAttributes *attributes = [super finalLayoutAttributesForDisappearingItemAtIndexPath:itemIndexPath];
    id<IGListCollectionViewDelegateLayout> delegate = (id<IGListCollectionViewDelegateLayout>)self.collectionView.delegate;
    if ([delegate respondsToSelector:@selector(collectionView:layout:customizedFinalLayoutAttributes:atIndexPath:)]) {
        return [delegate collectionView:self.collectionView
                                 layout:self
        customizedFinalLayoutAttributes:attributes
                            atIndexPath:itemIndexPath];
    }
    return attributes;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    IGAssertMainThread();

    NSMutableArray *result = [NSMutableArray new];

    const NSRange range = [self _rangeOfSectionsInRect:rect];
    if (range.location == NSNotFound) {
        return nil;
    }

    for (NSInteger section = range.location; section < NSMaxRange(range); section++) {
        const NSInteger itemCount = _sectionData[section].itemBounds.size();

        // do not add headers if there are no items
        if (itemCount > 0 || self.showHeaderWhenEmpty) {
            for (NSString *elementKind in _supplementaryAttributesCache.allKeys) {
                NSIndexPath *indexPath = indexPathForSection(section);
                UICollectionViewLayoutAttributes *attributes = [self layoutAttributesForSupplementaryViewOfKind:elementKind
                                                                                                    atIndexPath:indexPath];
                // do not add zero height headers/footers or headers/footers that are outside the rect
                const CGRect frame = attributes.frame;
                const CGRect intersection = CGRectIntersection(frame, rect);
                if (attributes && !CGRectIsEmpty(intersection) && CGRectGetLengthInDirection(frame, self.scrollDirection) > 0.0) {
                    [result addObject:attributes];
                }
            }
        }

        // add all cells within the rect, return early if it starts iterating outside
        for (NSInteger item = 0; item < itemCount; item++) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
            UICollectionViewLayoutAttributes *attributes = [self layoutAttributesForItemAtIndexPath:indexPath];
            if (CGRectIntersectsRect(attributes.frame, rect)) {
                [result addObject:attributes];
            }
        }
    }

    return result;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    IGAssertMainThread();
    IGParameterAssert(indexPath != nil);

    UICollectionViewLayoutAttributes *attributes = _attributesCache[indexPath];
    if (attributes != nil) {
        return attributes;
    }

    // avoid OOB errors
    const NSInteger section = indexPath.section;
    const NSInteger item = indexPath.item;
    if (section >= _sectionData.size()
        || item >= _sectionData[section].itemBounds.size()) {
        return nil;
    }

    attributes = [[[self class] layoutAttributesClass] layoutAttributesForCellWithIndexPath:indexPath];
    attributes.frame = _sectionData[indexPath.section].itemBounds[indexPath.item];
    adjustZIndexForAttributes(attributes);
    _attributesCache[indexPath] = attributes;
    return attributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath {
    IGAssertMainThread();
    IGParameterAssert(indexPath != nil);

    UICollectionViewLayoutAttributes *attributes = _supplementaryAttributesCache[elementKind][indexPath];
    if (attributes != nil) {
        return attributes;
    }

    // avoid OOB errors
    const NSInteger section = indexPath.section;
    if (section >= _sectionData.size()) {
        return nil;
    }

    UICollectionView *collectionView = self.collectionView;
    const IGListSectionEntry entry = _sectionData[section];
    const CGFloat minOffset = CGRectGetMinInDirection(entry.bounds, self.scrollDirection);

    CGRect frame = CGRectZero;

    if ([elementKind isEqualToString:UICollectionElementKindSectionHeader]) {
        frame = entry.headerBounds;

        if (self.stickyHeaders) {
            CGFloat offset = CGPointGetCoordinateInDirection(collectionView.contentOffset, self.scrollDirection) + self.topContentInset + self.stickyHeaderYOffset;

            if (section + 1 == _sectionData.size()) {
                offset = MAX(minOffset, offset);
            } else {
                const CGFloat maxOffset = CGRectGetMinInDirection(_sectionData[section + 1].bounds, self.scrollDirection) - CGRectGetLengthInDirection(frame, self.scrollDirection);
                offset = MIN(MAX(minOffset, offset), maxOffset);
            }
            switch (self.scrollDirection) {
                case UICollectionViewScrollDirectionVertical:
                    frame.origin.y = offset;
                    break;
                case UICollectionViewScrollDirectionHorizontal:
                    frame.origin.x = offset;
                    break;
            }
        }
    } else if ([elementKind isEqualToString:UICollectionElementKindSectionFooter]) {
        frame = entry.footerBounds;
    }

    if (CGRectIsEmpty(frame)) {
        // Just like UICollectionViewFlowLayout, if the header/footer size is empty, do not not return an attribute.
        // If we did return something, calling [UICollectionView layoutAttributesForSupplementaryElementOfKind...] would too,
        // which could then crash if the UICollectionViewDelegate is not expecting to actually return a supplimentary view.
        return nil;
    } else {
        attributes = [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:elementKind withIndexPath:indexPath];
        attributes.frame = frame;
        adjustZIndexForAttributes(attributes);
        _supplementaryAttributesCache[elementKind][indexPath] = attributes;
        return attributes;
    }
}

- (CGSize)collectionViewContentSize {
    IGAssertMainThread();

    const NSInteger sectionCount = _sectionData.size();

    if (sectionCount == 0) {
        return CGSizeZero;
    }

    const IGListSectionEntry section = _sectionData[sectionCount - 1];
    UICollectionView *collectionView = self.collectionView;
    const UIEdgeInsets contentInset = collectionView.ig_contentInset;
    switch (self.scrollDirection) {
        case UICollectionViewScrollDirectionVertical: {
            const CGFloat height = CGRectGetMaxY(section.bounds) + section.insets.bottom;
            return CGSizeMake(CGRectGetWidth(collectionView.bounds) - contentInset.left - contentInset.right, height);
        }
        case UICollectionViewScrollDirectionHorizontal: {
            const CGFloat width = CGRectGetMaxX(section.bounds) + section.insets.right;
            return CGSizeMake(width, CGRectGetHeight(collectionView.bounds) - contentInset.top - contentInset.bottom);
        }
    }

}

- (void)invalidateLayoutWithContext:(IGListCollectionViewLayoutInvalidationContext *)context {
    BOOL hasInvalidatedItemIndexPaths = NO;
    if ([context respondsToSelector:@selector(invalidatedItemIndexPaths)]) {
        hasInvalidatedItemIndexPaths = [context invalidatedItemIndexPaths].count > 0;
    }

    if (hasInvalidatedItemIndexPaths
        || [context invalidateEverything]
        || context.ig_invalidateAllAttributes) {
        // invalidates all
        _minimumInvalidatedSection = 0;
    } else if ([context invalidateDataSourceCounts] && _minimumInvalidatedSection == NSNotFound) {
        // invalidate all if count changed and we don't have information on the minimum invalidated section
        _minimumInvalidatedSection = 0;
    }

    if (context.ig_invalidateSupplementaryAttributes) {
        [self _resetSupplementaryAttributesCache];
    }

    [super invalidateLayoutWithContext:context];
}

+ (Class)invalidationContextClass {
    return [IGListCollectionViewLayoutInvalidationContext class];
}

- (UICollectionViewLayoutInvalidationContext *)invalidationContextForBoundsChange:(CGRect)newBounds {
    const CGRect oldBounds = self.collectionView.bounds;

    IGListCollectionViewLayoutInvalidationContext *context =
    (IGListCollectionViewLayoutInvalidationContext *)[super invalidationContextForBoundsChange:newBounds];
    context.ig_invalidateSupplementaryAttributes = YES;
    if (!CGSizeEqualToSize(oldBounds.size, newBounds.size)) {
        context.ig_invalidateAllAttributes = YES;
    }
    return context;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    const CGRect oldBounds = self.collectionView.bounds;

    // always invalidate for size changes
    if (!CGSizeEqualToSize(oldBounds.size, newBounds.size)) {
        return YES;
    }

    // if the y origin has changed, only invalidate when using sticky headers
    if (CGRectGetMinInDirection(newBounds, self.scrollDirection) != CGRectGetMinInDirection(oldBounds, self.scrollDirection)) {
        return self.stickyHeaders;
    }

    return NO;
}

- (void)prepareLayout {
    [self _calculateLayoutIfNeeded];
}

#pragma mark - Public API

- (void)setStickyHeaderYOffset:(CGFloat)stickyHeaderYOffset {
    IGAssertMainThread();

    if (_stickyHeaderYOffset != stickyHeaderYOffset) {
        _stickyHeaderYOffset = stickyHeaderYOffset;

        IGListCollectionViewLayoutInvalidationContext *invalidationContext = [IGListCollectionViewLayoutInvalidationContext new];
        invalidationContext.ig_invalidateSupplementaryAttributes = YES;
        [self invalidateLayoutWithContext:invalidationContext];
    }
}

#pragma mark - Private API

- (void)_calculateNormal:(UICollectionView *)collectionView
adjustedCollectionViewBounds:(const CGRect &)adjustedCollectionViewBounds
                delegate:(id<UICollectionViewDelegateFlowLayout>)delegate
itemCoordInFixedDirection:(CGFloat &)itemCoordInFixedDirection
itemCoordInScrollDirection:(CGFloat &)itemCoordInScrollDirection
nextRowCoordInScrollDirection:(CGFloat &)nextRowCoordInScrollDirection
    rollingSectionBounds:(CGRect &)rollingSectionBounds
                 section:(NSInteger)section
{
    const NSInteger itemCount = [collectionView numberOfItemsInSection:section];
    const BOOL itemsEmpty = itemCount == 0;
    const BOOL hideHeaderWhenItemsEmpty = itemsEmpty && !self.showHeaderWhenEmpty;
    _sectionData[section].itemBounds = std::vector<CGRect>(itemCount);
    
    const CGSize headerSize = [delegate collectionView:collectionView layout:self referenceSizeForHeaderInSection:section];
    const CGSize footerSize = [delegate collectionView:collectionView layout:self referenceSizeForFooterInSection:section];
    const UIEdgeInsets insets = [delegate collectionView:collectionView layout:self insetForSectionAtIndex:section];
    const CGFloat lineSpacing = [delegate collectionView:collectionView layout:self minimumLineSpacingForSectionAtIndex:section];
    const CGFloat interitemSpacing = [delegate collectionView:collectionView layout:self minimumInteritemSpacingForSectionAtIndex:section];
    
    const CGSize paddedCollectionViewSize = UIEdgeInsetsInsetRect(adjustedCollectionViewBounds, insets).size;
    const UICollectionViewScrollDirection fixedDirection = self.scrollDirection == UICollectionViewScrollDirectionHorizontal ? UICollectionViewScrollDirectionVertical : UICollectionViewScrollDirectionHorizontal;
    const CGFloat paddedLengthInFixedDirection = CGSizeGetLengthInDirection(paddedCollectionViewSize, fixedDirection);
    const CGFloat headerLengthInScrollDirection = hideHeaderWhenItemsEmpty ? 0 : CGSizeGetLengthInDirection(headerSize, self.scrollDirection);
    const CGFloat footerLengthInScrollDirection = hideHeaderWhenItemsEmpty ? 0 : CGSizeGetLengthInDirection(footerSize, self.scrollDirection);
    const BOOL headerExists = headerLengthInScrollDirection > 0;
    const BOOL footerExists = footerLengthInScrollDirection > 0;
    
    // start the section accounting for the header size
    // header length in scroll direction is subtracted from the sectionBounds when calculating the header bounds after items are done
    // this bumps the first row of items over enough to make room for the header
    itemCoordInScrollDirection += headerLengthInScrollDirection;
    nextRowCoordInScrollDirection += headerLengthInScrollDirection;
    
    // add the leading inset in fixed direction in case the section falls on the same row as the previous
    // if the section is newlined then the coord in fixed direction is reset
    itemCoordInFixedDirection += UIEdgeInsetsLeadingInsetInDirection(insets, fixedDirection);
    
    // the farthest in the fixed direction the frame of an item in this section can go
    const CGFloat maxCoordinateInFixedDirection = CGRectGetLengthInDirection(adjustedCollectionViewBounds, fixedDirection) - UIEdgeInsetsTrailingInsetInDirection(insets, fixedDirection);
    
    for (NSInteger item = 0; item < itemCount; item++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
        const CGSize size = [delegate collectionView:collectionView layout:self sizeForItemAtIndexPath:indexPath];
        
        IGAssert(CGSizeGetLengthInDirection(size, fixedDirection) <= paddedLengthInFixedDirection
                 || fabs(CGSizeGetLengthInDirection(size, fixedDirection) - paddedLengthInFixedDirection) < FLT_EPSILON,
                 @"%@ of item %li in section %li (%.0f pt) must be less than or equal to container (%.0f pt) accounting for section insets %@",
                 self.scrollDirection == UICollectionViewScrollDirectionVertical ? @"Width" : @"Height",
                 (long)item,
                 (long)section,
                 CGSizeGetLengthInDirection(size, fixedDirection),
                 CGRectGetLengthInDirection(adjustedCollectionViewBounds, fixedDirection),
                 NSStringFromUIEdgeInsets(insets));
        
        CGFloat itemLengthInFixedDirection = MIN(CGSizeGetLengthInDirection(size, fixedDirection), paddedLengthInFixedDirection);
        
        // if the origin and length in fixed direction of the item busts the size of the container
        // or if this is the first item and the header has a non-zero size
        // newline to the next row and reset
        // define epsilon to avoid float overflow issue
        const CGFloat epsilon = 1.0;
        if (itemCoordInFixedDirection + itemLengthInFixedDirection > maxCoordinateInFixedDirection + epsilon
            || (item == 0 && headerExists)) {
            itemCoordInScrollDirection = nextRowCoordInScrollDirection;
            itemCoordInFixedDirection = UIEdgeInsetsLeadingInsetInDirection(insets, fixedDirection);
            
            
            // if newlining, always append line spacing unless its the very first item of the section
            if (item > 0) {
                itemCoordInScrollDirection += lineSpacing;
            }
        }
        
        const CGFloat distanceToEdge = paddedLengthInFixedDirection - (itemCoordInFixedDirection + itemLengthInFixedDirection);
        if (self.stretchToEdge && distanceToEdge > 0 && distanceToEdge <= epsilon) {
            itemLengthInFixedDirection = paddedLengthInFixedDirection - itemCoordInFixedDirection;
        }
        
        const CGRect rawFrame = (self.scrollDirection == UICollectionViewScrollDirectionVertical) ?
        CGRectMake(itemCoordInFixedDirection,
                   itemCoordInScrollDirection + insets.top,
                   itemLengthInFixedDirection,
                   size.height) :
        CGRectMake(itemCoordInScrollDirection + insets.left,
                   itemCoordInFixedDirection,
                   size.width,
                   itemLengthInFixedDirection);
        const CGRect frame = IGListRectIntegralScaled(rawFrame);
        
        _sectionData[section].itemBounds[item] = frame;
        
        // track the max size of the row to find the coord of the next row, adjust for leading inset while iterating items
        nextRowCoordInScrollDirection = MAX(CGRectGetMaxInDirection(frame, self.scrollDirection) - UIEdgeInsetsLeadingInsetInDirection(insets, self.scrollDirection), nextRowCoordInScrollDirection);
        
        // increase the rolling coord in fixed direction appropriately and add item spacing for all items on the same row
        itemCoordInFixedDirection += itemLengthInFixedDirection + interitemSpacing;
        
        // union the rolling section bounds
        if (item == 0) {
            rollingSectionBounds = frame;
        } else {
            rollingSectionBounds = CGRectUnion(rollingSectionBounds, frame);
        }
    }
    
    const CGRect headerBounds = self.scrollDirection == UICollectionViewScrollDirectionVertical ?
    CGRectMake(insets.left,
               itemsEmpty ? CGRectGetMaxY(rollingSectionBounds) : CGRectGetMinY(rollingSectionBounds) - headerSize.height,
               paddedLengthInFixedDirection,
               hideHeaderWhenItemsEmpty ? 0 : headerSize.height) :
    CGRectMake(itemsEmpty ? CGRectGetMaxX(rollingSectionBounds) : CGRectGetMinX(rollingSectionBounds) - headerSize.width,
               insets.top,
               hideHeaderWhenItemsEmpty ? 0 : headerSize.width,
               paddedLengthInFixedDirection);
    
    _sectionData[section].headerBounds = headerBounds;
    
    if (itemsEmpty) {
        rollingSectionBounds = headerBounds;
    }
    
    const CGRect footerBounds = (self.scrollDirection == UICollectionViewScrollDirectionVertical) ?
    CGRectMake(insets.left,
               CGRectGetMaxY(rollingSectionBounds),
               paddedLengthInFixedDirection,
               hideHeaderWhenItemsEmpty ? 0 : footerSize.height) :
    CGRectMake(CGRectGetMaxX(rollingSectionBounds) + insets.right,
               insets.top,
               hideHeaderWhenItemsEmpty ? 0 : footerSize.width,
               paddedLengthInFixedDirection);
    
    _sectionData[section].footerBounds = footerBounds;
    
    // union the header before setting the bounds of the  section
    // only do this when the header has a size, otherwise the union stretches to box empty space
    if (headerExists) {
        rollingSectionBounds = CGRectUnion(rollingSectionBounds, headerBounds);
    }
    if (footerExists) {
        rollingSectionBounds = CGRectUnion(rollingSectionBounds, footerBounds);
    }
    
    _sectionData[section].bounds = rollingSectionBounds;
    _sectionData[section].insets = insets;
    
    // bump the coord for the next section with the right insets
    itemCoordInFixedDirection += UIEdgeInsetsTrailingInsetInDirection(insets, fixedDirection);
    
    // find the farthest point in the section and add the trailing inset to find the next row's coord
    nextRowCoordInScrollDirection = MAX(nextRowCoordInScrollDirection, CGRectGetMaxInDirection(rollingSectionBounds, self.scrollDirection) + UIEdgeInsetsTrailingInsetInDirection(insets, self.scrollDirection));
    
    // keep track of coordinates for partial invalidation
    _sectionData[section].lastItemCoordInScrollDirection = itemCoordInScrollDirection;
    _sectionData[section].lastItemCoordInFixedDirection = itemCoordInFixedDirection;
    _sectionData[section].lastNextRowCoordInScrollDirection = nextRowCoordInScrollDirection;
}

- (void)_calculateWaterFlow:(UICollectionView *)collectionView
                columnCount:(NSInteger)columnCount
adjustedCollectionViewBounds:(const CGRect &)adjustedCollectionViewBounds
                delegate:(id<UICollectionViewDelegateFlowLayout>)delegate
itemCoordInFixedDirection:(CGFloat &)itemCoordInFixedDirection
itemCoordInScrollDirection:(CGFloat &)itemCoordInScrollDirection
nextRowCoordInScrollDirection:(CGFloat &)nextRowCoordInScrollDirection
    rollingSectionBounds:(CGRect &)rollingSectionBounds
                 section:(NSInteger)section
{
    const NSInteger itemCount = [collectionView numberOfItemsInSection:section];
    const BOOL itemsEmpty = itemCount == 0;
    const BOOL hideHeaderWhenItemsEmpty = itemsEmpty && !self.showHeaderWhenEmpty;
    _sectionData[section].itemBounds = std::vector<CGRect>(itemCount);
    _sectionData[section].columnData = std::vector<IGListSectionColumnEntry>(columnCount);
    
    const CGSize headerSize = [delegate collectionView:collectionView layout:self referenceSizeForHeaderInSection:section];
    const CGSize footerSize = [delegate collectionView:collectionView layout:self referenceSizeForFooterInSection:section];
    const UIEdgeInsets insets = [delegate collectionView:collectionView layout:self insetForSectionAtIndex:section];
    const CGFloat lineSpacing = [delegate collectionView:collectionView layout:self minimumLineSpacingForSectionAtIndex:section];
    const CGFloat interitemSpacing = [delegate collectionView:collectionView layout:self minimumInteritemSpacingForSectionAtIndex:section];
    
    const CGSize paddedCollectionViewSize = UIEdgeInsetsInsetRect(adjustedCollectionViewBounds, insets).size;
    const UICollectionViewScrollDirection fixedDirection = self.scrollDirection == UICollectionViewScrollDirectionHorizontal ? UICollectionViewScrollDirectionVertical : UICollectionViewScrollDirectionHorizontal;
    
    const CGFloat paddedLengthInFixedDirection = CGSizeGetLengthInDirection(paddedCollectionViewSize, fixedDirection);
    const CGFloat paddedColumnLenInFixedDirection = CGSizeGetColumnLenInDirection(paddedCollectionViewSize, columnCount, interitemSpacing, fixedDirection);
    
    const CGFloat headerLengthInScrollDirection = hideHeaderWhenItemsEmpty ? 0 : CGSizeGetLengthInDirection(headerSize, self.scrollDirection);
    const CGFloat footerLengthInScrollDirection = hideHeaderWhenItemsEmpty ? 0 : CGSizeGetLengthInDirection(footerSize, self.scrollDirection);
    const BOOL headerExists = headerLengthInScrollDirection > 0;
    const BOOL footerExists = footerLengthInScrollDirection > 0;
    
    // start the section accounting for the header size
    // header length in scroll direction is subtracted from the sectionBounds when calculating the header bounds after items are done
    // this bumps the first row of items over enough to make room for the header
    nextRowCoordInScrollDirection += headerLengthInScrollDirection;
    CGFloat sectionCoordInFixedDirection = UIEdgeInsetsLeadingInsetInDirection(insets, fixedDirection);

    for (NSInteger column = 0; column < columnCount; column++) {
        _sectionData[section].columnData[column].coordInFixedDirection = sectionCoordInFixedDirection + column * (paddedColumnLenInFixedDirection + interitemSpacing);
        _sectionData[section].columnData[column].lastCoordInScrollDirection = nextRowCoordInScrollDirection;
    }
    
    for (NSInteger item = 0; item < itemCount; item++)
    {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
        const CGSize size = [delegate collectionView:collectionView layout:self sizeForItemAtIndexPath:indexPath];
        CGFloat itemLenInFixedDirection = MIN(CGSizeGetLengthInDirection(size, fixedDirection), paddedColumnLenInFixedDirection);
        
        // 计算每个item的时候，都对每列的最大高度进行一次排序，每次都把当前item加到高度最低的那一列上
        auto iter = std::min_element(_sectionData[section].columnData.begin(),
                                     _sectionData[section].columnData.end(),
                                     [](const IGListSectionColumnEntry& lhs, const IGListSectionColumnEntry& rhs) {
            return lhs.lastCoordInScrollDirection < rhs.lastCoordInScrollDirection ;
        });
        CGFloat coordInFixedDirection = iter->coordInFixedDirection;
        CGFloat coordInScrollDirection = iter->lastCoordInScrollDirection;
        
        // 非第一行的话，需要加上行间距
        if (item >= columnCount ) {
            coordInScrollDirection += lineSpacing;
        }
        
        const CGRect rawFrame = (self.scrollDirection == UICollectionViewScrollDirectionVertical) ?
        CGRectMake(coordInFixedDirection,
                   coordInScrollDirection + insets.top,
                   itemLenInFixedDirection,
                   size.height) :
        CGRectMake(coordInScrollDirection + insets.left,
                   coordInFixedDirection,
                   size.width,
                   itemLenInFixedDirection);
        const CGRect frame = IGListRectIntegralScaled(rawFrame);
        _sectionData[section].itemBounds[item] = frame;
        
        const CGFloat lastCoordInScrollDirection = (self.scrollDirection == UICollectionViewScrollDirectionVertical) ? coordInScrollDirection + size.height : coordInScrollDirection + size.width;
        iter->lastCoordInScrollDirection = lastCoordInScrollDirection;
        
        
        // union the rolling section bounds
        if (item == 0) {
            rollingSectionBounds = frame;
        } else {
            rollingSectionBounds = CGRectUnion(rollingSectionBounds, frame);
        }
    }
    
    const CGRect headerBounds = self.scrollDirection == UICollectionViewScrollDirectionVertical ?
    CGRectMake(insets.left,
               itemsEmpty ? CGRectGetMaxY(rollingSectionBounds) : CGRectGetMinY(rollingSectionBounds) - headerSize.height,
               paddedLengthInFixedDirection,
               hideHeaderWhenItemsEmpty ? 0 : headerSize.height) :
    CGRectMake(itemsEmpty ? CGRectGetMaxX(rollingSectionBounds) : CGRectGetMinX(rollingSectionBounds) - headerSize.width,
               insets.top,
               hideHeaderWhenItemsEmpty ? 0 : headerSize.width,
               paddedLengthInFixedDirection);
    
    _sectionData[section].headerBounds = headerBounds;
    
    if (itemsEmpty) {
        rollingSectionBounds = headerBounds;
    }
    
    const CGRect footerBounds = (self.scrollDirection == UICollectionViewScrollDirectionVertical) ?
    CGRectMake(insets.left,
               CGRectGetMaxY(rollingSectionBounds),
               paddedLengthInFixedDirection,
               hideHeaderWhenItemsEmpty ? 0 : footerSize.height) :
    CGRectMake(CGRectGetMaxX(rollingSectionBounds) + insets.right,
               insets.top,
               hideHeaderWhenItemsEmpty ? 0 : footerSize.width,
               paddedLengthInFixedDirection);
    
    _sectionData[section].footerBounds = footerBounds;
    
    // union the header before setting the bounds of the  section
    // only do this when the header has a size, otherwise the union stretches to box empty space
    if (headerExists) {
        rollingSectionBounds = CGRectUnion(rollingSectionBounds, headerBounds);
    }
    if (footerExists) {
        rollingSectionBounds = CGRectUnion(rollingSectionBounds, footerBounds);
    }
    
    _sectionData[section].bounds = rollingSectionBounds;
    _sectionData[section].insets = insets;
    
    // bump the coord for the next section with the right insets
    sectionCoordInFixedDirection += UIEdgeInsetsTrailingInsetInDirection(insets, fixedDirection);
    itemCoordInFixedDirection = sectionCoordInFixedDirection;
    // find the farthest point in the section and add the trailing inset to find the next row's coord
    nextRowCoordInScrollDirection = MAX(nextRowCoordInScrollDirection, CGRectGetMaxInDirection(rollingSectionBounds, self.scrollDirection) + UIEdgeInsetsTrailingInsetInDirection(insets, self.scrollDirection));
    
    // keep track of coordinates for partial invalidation
//    std::sort(_sectionData[section].columnData.begin(), _sectionData[section].columnData.end(), sortColumnEntry);
    auto iter = std::max_element(_sectionData[section].columnData.begin(),
                                 _sectionData[section].columnData.end(),
                                 [](const IGListSectionColumnEntry& lhs, const IGListSectionColumnEntry& rhs) {
        return lhs.lastCoordInScrollDirection < rhs.lastCoordInScrollDirection ;
    });
    _sectionData[section].lastItemCoordInScrollDirection = iter -> lastCoordInScrollDirection;
    _sectionData[section].lastItemCoordInFixedDirection = itemCoordInFixedDirection;
    _sectionData[section].lastNextRowCoordInScrollDirection = nextRowCoordInScrollDirection;
    
    itemCoordInScrollDirection = nextRowCoordInScrollDirection;
}

- (void)_calculateLayoutIfNeeded
{
    if (_minimumInvalidatedSection == NSNotFound) {
        return;
    }

    // purge attribute caches so they are rebuilt
    [_attributesCache removeAllObjects];
    [self _resetSupplementaryAttributesCache];

    UICollectionView *collectionView = self.collectionView;
    id<UICollectionViewDelegateFlowLayout> delegate = (id<UICollectionViewDelegateFlowLayout>)collectionView.delegate;

    const NSInteger sectionCount = [collectionView numberOfSections];
    const UIEdgeInsets contentInset = collectionView.ig_contentInset;
    const CGRect adjustedCollectionViewBounds = UIEdgeInsetsInsetRect(collectionView.bounds, contentInset);

    _sectionData.resize(sectionCount);

    CGFloat itemCoordInScrollDirection = 0.0;
    CGFloat itemCoordInFixedDirection = 0.0;
    CGFloat nextRowCoordInScrollDirection = 0.0;

    // union item frames and optionally the header to find a bounding box of the entire section
    CGRect rollingSectionBounds = CGRectZero;

    // populate last valid section information
    const NSInteger lastValidSection = _minimumInvalidatedSection - 1;
    if (lastValidSection >= 0 && lastValidSection < sectionCount) {
        itemCoordInScrollDirection = _sectionData[lastValidSection].lastItemCoordInScrollDirection;
        itemCoordInFixedDirection = _sectionData[lastValidSection].lastItemCoordInFixedDirection;
        nextRowCoordInScrollDirection = _sectionData[lastValidSection].lastNextRowCoordInScrollDirection;
        rollingSectionBounds = _sectionData[lastValidSection].bounds;
    }

    for (NSInteger section = _minimumInvalidatedSection; section < sectionCount; section++)
    {
        id<WBCollectionViewDelegateFlowLayout> flowLayout = (id<WBCollectionViewDelegateFlowLayout>)delegate;
        const BOOL isWaterFlow = [flowLayout collectionView:collectionView layout:self isWaterFlowInSection:section];
        const NSInteger column = [flowLayout collectionView:collectionView layout:self waterFlowColumnInSection:section];
        if (isWaterFlow && column > 1) {
            [self _calculateWaterFlow:collectionView columnCount:column adjustedCollectionViewBounds:adjustedCollectionViewBounds delegate:delegate itemCoordInFixedDirection:itemCoordInFixedDirection itemCoordInScrollDirection:itemCoordInScrollDirection nextRowCoordInScrollDirection:nextRowCoordInScrollDirection rollingSectionBounds:rollingSectionBounds section:section];
        }else{
            [self _calculateNormal:collectionView adjustedCollectionViewBounds:adjustedCollectionViewBounds delegate:delegate itemCoordInFixedDirection:itemCoordInFixedDirection itemCoordInScrollDirection:itemCoordInScrollDirection nextRowCoordInScrollDirection:nextRowCoordInScrollDirection rollingSectionBounds:rollingSectionBounds section:section];
        }
    }
    
    _minimumInvalidatedSection = NSNotFound;
}

- (NSRange)_rangeOfSectionsInRect:(CGRect)rect
{
    NSRange result = NSMakeRange(NSNotFound, 0);
    
    const NSInteger sectionCount = _sectionData.size();
    for (NSInteger section = 0; section < sectionCount; section++) {
        IGListSectionEntry entry = _sectionData[section];
        if (entry.isValid() && CGRectIntersectsRect(entry.bounds, rect)) {
            const NSRange sectionRange = NSMakeRange(section, 1);
            if (result.location == NSNotFound) {
                result = sectionRange;
            } else {
                result = NSUnionRange(result, sectionRange);
            }
        }
    }
    
    return result;
}

- (void)_resetSupplementaryAttributesCache {
    [_supplementaryAttributesCache enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSMutableDictionary<NSIndexPath *,UICollectionViewLayoutAttributes *> * _Nonnull attributesCache, BOOL * _Nonnull stop) {
        [attributesCache removeAllObjects];
    }];
}

#pragma mark - Minimum Invalidated Section

- (void)didModifySection:(NSInteger)modifiedSection {
    _minimumInvalidatedSection = IGListMergeMinimumInvalidatedSection(_minimumInvalidatedSection, modifiedSection);
}

@end
