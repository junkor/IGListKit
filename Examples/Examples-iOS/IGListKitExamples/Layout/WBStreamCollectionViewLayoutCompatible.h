//
//  WBStreamCollectionViewLayoutCompatible.h
//  IGListKitExamples
//
//  Created by junlin3 on 2021/1/8.
//  Copyright © 2021 Instagram. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol WBStreamCollectionViewLayoutCompatible <NSObject>

- (void)didModifySection:(NSInteger)modifiedSection;

@end

NS_ASSUME_NONNULL_END
