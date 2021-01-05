//
//  AttributeCache.m
//  IGListKitExamples
//
//  Created by junlin3 on 2020/12/21.
//  Copyright © 2020 Instagram. All rights reserved.
//

#import "AttributeCache.h"


@interface AttributeCache ()

@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<UICollectionViewLayoutAttributes *> *> *attributes;

// private
- (NSMutableArray<UICollectionViewLayoutAttributes *> *)mutableAttributesForSection:(NSInteger)section;

@end

@implementation AttributeCache

- (instancetype)init
{
    if (self = [super init]) {
        _attributes = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSMutableArray<UICollectionViewLayoutAttributes *> *)mutableAttributesForSection:(NSInteger)section
{
    NSNumber *key = @(section);
    NSMutableArray *attributes = [self.attributes objectForKey:key];
    if (attributes == nil) {
        attributes = [NSMutableArray array];
        [self.attributes setObject:attributes forKey:key];
    }
    return attributes;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)attributesForSection:(NSInteger)section
{
    return [[self mutableAttributesForSection:section] copy];
}

- (UICollectionViewLayoutAttributes *)attributeForIndexPath:(NSIndexPath *)indexPath
{
    NSArray<UICollectionViewLayoutAttributes *> *attributes = [self attributesForSection:indexPath.section];
    if (indexPath.item < attributes.count) {
        return attributes[indexPath.item];
    }
    return nil;
}

- (void)addAttributes:(NSArray<UICollectionViewLayoutAttributes *> *)attributes forSection:(NSInteger)section
{
    [self.attributes setObject:[attributes mutableCopy] forKey:@(section)];
}

- (void)addAttribute:(UICollectionViewLayoutAttributes *)attribute forIndexPath:(NSIndexPath *)indexPath
{
    NSMutableArray<UICollectionViewLayoutAttributes *> *sectionAttributes = [self mutableAttributesForSection:indexPath.section];
    if (sectionAttributes.count > indexPath.item) {
        if (attribute) {
            [sectionAttributes replaceObjectAtIndex:indexPath.item withObject:attribute];
        }else{
            [sectionAttributes removeObjectAtIndex:indexPath.item];
        }
    }
}

- (void)clearAttributes
{
    [self.attributes removeAllObjects];
}

- (void)clearAttributesForSection:(NSInteger)section
{
    [self.attributes removeObjectForKey:@(section)];
}

- (void)clearAttributeForIndexPath:(NSIndexPath *)indexPath
{
    NSMutableArray<UICollectionViewLayoutAttributes *> *attributes = [self mutableAttributesForSection:indexPath.section];
    if (indexPath.item < attributes.count) {
        [attributes removeObjectAtIndex:indexPath.item];
    }
}


@end
