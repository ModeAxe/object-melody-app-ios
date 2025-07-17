import UIKit

class SegmentationManager {
    private var strategy: SegmentationStrategy
    
    init(strategy: SegmentationStrategy) {
        self.strategy = strategy
    }
    
    func setStrategy(_ strategy: SegmentationStrategy) {
        self.strategy = strategy
    }
    
    func segmentObject(in image: UIImage, completion: @escaping (UIImage?) -> Void) {
        strategy.segmentObject(in: image, completion: completion)
    }
    
    var currentStrategyName: String {
        strategy.name
    }
} 