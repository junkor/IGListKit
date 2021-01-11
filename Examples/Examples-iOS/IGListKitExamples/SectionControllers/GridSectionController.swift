/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import IGListKit
import IGListSwiftKit
import UIKit

final class GridItem: NSObject {

    let color: UIColor
    let itemCount: Int

    var items: [String] = []

    init(color: UIColor, itemCount: Int) {
        self.color = color
        self.itemCount = itemCount

        super.init()

        self.items = computeItems()
    }

    private func computeItems() -> [String] {
        return [Int](1...itemCount).map {
            String(describing: $0)
        }
    }
}

extension GridItem: ListDiffable {

    func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        return self === object ? true : self.isEqual(object)
    }

}

final class GridSectionController: ListSectionController {

    private var object: GridItem?
    private let isReorderable: Bool

    required init(isReorderable: Bool = false) {
        self.isReorderable = isReorderable
        super.init()
        self.minimumInteritemSpacing = 1
        self.minimumLineSpacing = 1
    }

    override func numberOfItems() -> Int {
        return object?.itemCount ?? 0
    }

    override func sizeForItem(at index: Int) -> CGSize {
        let width = collectionContext?.containerSize.width ?? 0

        if section == 1 {
            return CGSize(width: width / 2.0, height: 80)
        }

        var itemSize: CGFloat = 0
        switch index {
        case 0:
            itemSize = 50
        case 1:
            itemSize = 120
        case 2:
            itemSize = 100
        case 3:
            itemSize = 30
        case 4:
            itemSize = 100
        case 5:
            itemSize = 50
        case 6:
            itemSize = 40
        default:
            itemSize = floor(width / 4)
        }
        return CGSize(width: 194, height: itemSize)
    }

    override func isWaterFlow() -> Bool {
        if self.section == 1 {
            return false
        }
        return true
    }

    override func waterFlowColumn() -> Int {
        return 3
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let cell: CenterLabelCell = collectionContext?.dequeueReusableCell(for: self, at: index) else {
            fatalError()
        }
        cell.text = object?.items[index] ?? "undefined"
        cell.backgroundColor = object?.color
        return cell
    }

    override func didUpdate(to object: Any) {
        self.object = object as? GridItem
    }

    override func canMoveItem(at index: Int) -> Bool {
        return isReorderable
    }

    override func moveObject(from sourceIndex: Int, to destinationIndex: Int) {
        guard let object = object else { return }
        let item = object.items.remove(at: sourceIndex)
        object.items.insert(item, at: destinationIndex)
    }
}
