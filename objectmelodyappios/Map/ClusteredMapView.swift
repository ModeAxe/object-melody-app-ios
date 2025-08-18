import SwiftUI
import MapKit

struct ClusteredMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var annotations: [TraceAnnotation]
    var onCameraChanged: (MKCoordinateRegion) -> Void
    var onAnnotationTapped: (TraceAnnotation) -> Void
    var selectionCoordinate: CLLocationCoordinate2D?
    var onMapTapped: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.region = region
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "Cluster")
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "TraceImage")
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "SelectionPin")

        // Tap recognizer for map taps (not on annotations)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        tap.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tap)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Do not force-set region here to avoid fighting user gestures
        // Diff annotations by id to avoid full refresh
        let existing = uiView.annotations.compactMap { $0 as? TraceAnnotation }
        let existingIds = Set(existing.map { $0.id })
        let newIds = Set(annotations.map { $0.id })

        // Remove
        let toRemove = existing.filter { !newIds.contains($0.id) }
        uiView.removeAnnotations(toRemove)

        // Add
        let toAdd = annotations.filter { !existingIds.contains($0.id) }
        uiView.addAnnotations(toAdd)

        // Update selection annotation
        context.coordinator.updateSelectionAnnotation(on: uiView, coordinate: selectionCoordinate)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: ClusteredMapView
        private var cameraChangeWorkItem: DispatchWorkItem?
        private var selectionAnnotation: MKPointAnnotation?
        init(_ parent: ClusteredMapView) { self.parent = parent }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            // Sync initial region once when map finishes rendering
            if fullyRendered {
                parent.region = mapView.region
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: "Cluster", for: cluster) as! MKMarkerAnnotationView
                v.annotation = cluster
                v.clusteringIdentifier = "trace"
                v.displayPriority = .required
                v.markerTintColor = .systemBlue
                v.glyphText = "\(cluster.memberAnnotations.count)"
                v.canShowCallout = false
                return v
            }
            if annotation is MKPointAnnotation {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: "SelectionPin", for: annotation)
                v.annotation = annotation
                v.image = Self.makeGradientPinImage(size: CGSize(width: 30, height: 30),
                                                    top: .purple,
                                                    bottom: .lightGray)
                v.layer.shadowColor = UIColor.black.cgColor
                v.layer.shadowOpacity = 0.3
                v.layer.shadowRadius = 2
                v.layer.shadowOffset = CGSize(width: 0, height: 1)
                return v
            }
            guard let ann = annotation as? TraceAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "TraceImage", for: ann)
            v.annotation = ann
            v.clusteringIdentifier = "trace"
            v.displayPriority = .defaultHigh
            v.canShowCallout = false
            v.image = Self.makeGradientPinImage(size: CGSize(width: 25, height: 25),
                                                top: UIColor.systemMint,
                                                bottom: UIColor.systemPink)
            // Reset any reused transform
            v.transform = .identity
            // Shadow to match SwiftUI
            v.layer.shadowColor = UIColor.black.cgColor
            v.layer.shadowOpacity = 0.3
            v.layer.shadowRadius = 2
            v.layer.shadowOffset = CGSize(width: 0, height: 1)
            return v
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                // Zoom into cluster area
                let members = cluster.memberAnnotations
                var zoomRect = MKMapRect.null
                for m in members {
                    let point = MKMapPoint(m.coordinate)
                    let rect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
                    zoomRect = zoomRect.union(rect)
                }
                let insets = UIEdgeInsets(top: 60, left: 60, bottom: 60, right: 60)
                mapView.setVisibleMapRect(zoomRect, edgePadding: insets, animated: true)
                return
            }
            if let ann = view.annotation as? TraceAnnotation {
                // Enlarge selected pin
                UIView.animate(withDuration: 0.15) {
                    view.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
                }
                parent.onAnnotationTapped(ann)
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            // Restore size when deselected
            UIView.animate(withDuration: 0.15) {
                view.transform = .identity
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            cameraChangeWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.parent.onCameraChanged(mapView.region)
            }
            cameraChangeWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
        }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            // If tapping on an annotation view, ignore
            if mapView.hitTest(point, with: nil) is MKAnnotationView { return }
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onMapTapped(coord)
        }

        func updateSelectionAnnotation(on mapView: MKMapView, coordinate: CLLocationCoordinate2D?) {
            // If clearing selection
            guard let coordinate = coordinate else {
                if let existing = selectionAnnotation {
                    mapView.removeAnnotation(existing)
                    selectionAnnotation = nil
                }
                return
            }

            // If we already have a selection pin
            if let existing = selectionAnnotation {
                // If coordinate hasn't meaningfully changed, do nothing
                let dLat = abs(existing.coordinate.latitude - coordinate.latitude)
                let dLon = abs(existing.coordinate.longitude - coordinate.longitude)
                if dLat < 1e-7 && dLon < 1e-7 { return }
                // Just move the existing pin to avoid flicker
                existing.coordinate = coordinate
                return
            }

            // Otherwise add a new selection pin
            let ann = MKPointAnnotation()
            ann.coordinate = coordinate
            ann.title = "Your Trace"
            selectionAnnotation = ann
            mapView.addAnnotation(ann)
        }
    }
}
private extension ClusteredMapView.Coordinator {
    static func makeGradientPinImage(size: CGSize, top: UIColor, bottom: UIColor) -> UIImage? {
        let scale = UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(ovalIn: rect)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.clip()

            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let locations: [CGFloat] = [0.0, 1.0]
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) {
                ctx.cgContext.drawLinearGradient(gradient,
                                                 start: CGPoint(x: rect.midX, y: rect.minY),
                                                 end: CGPoint(x: rect.midX, y: rect.maxY),
                                                 options: [])
            }

            ctx.cgContext.resetClip()
            UIColor.white.setStroke()
            let strokePath = UIBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            strokePath.lineWidth = 1
            strokePath.stroke()
        }
    }
}
