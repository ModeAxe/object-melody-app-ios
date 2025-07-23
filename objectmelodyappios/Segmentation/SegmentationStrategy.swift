import UIKit

/// Protocol for plug-and-play image segmentation strategies.
protocol SegmentationStrategy {
    var name: String { get }
    
    func segmentObject(in image: UIImage, completion: @escaping (UIImage?) -> Void)
}
