//
//  AttributeCache.h
//  IGListKitExamples
//
//  Created by junlin3 on 2020/12/21.
//  Copyright © 2020 Instagram. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AttributeCache : NSObject

- (NSArray<UICollectionViewLayoutAttributes *> *)attributesForSection:(NSInteger)section;
- (UICollectionViewLayoutAttributes *)attributeForIndexPath:(NSIndexPath *)indexPath;

- (void)addAttributes:(NSArray<UICollectionViewLayoutAttributes *> *)attributes forSection:(NSInteger)section;
- (void)addAttribute:(UICollectionViewLayoutAttributes *)attribute forIndexPath:(NSIndexPath *)indexPath;

- (void)clearAttributes;
- (void)clearAttributesForSection:(NSInteger)section;
- (void)clearAttributeForIndexPath:(NSIndexPath *)indexPath;


@end

NS_ASSUME_NONNULL_END
