//
//  WBCollectionViewDelegateFlowLayout.h
//  IGListKitExamples
//
//  Created by junlin3 on 2021/1/5.
//  Copyright © 2021 Instagram. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol WBCollectionViewDelegateFlowLayout <UICollectionViewDelegateFlowLayout>

@required

/// 局部Section是否支持瀑布流形式的布局
/// @param collectionView
/// @param collectionViewLayout
/// @param section
- (BOOL)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout isWaterFlowInSection:(NSInteger)section;


/// 支持瀑布流的布局组，需要布局的列数（瀑布流使用等宽布局）
/// @param collectionView
/// @param collectionViewLayout
/// @param section
- (NSInteger)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout waterFlowColumnInSection:(NSInteger)section;

@end

NS_ASSUME_NONNULL_END
