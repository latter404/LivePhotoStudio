import SwiftUI
import AppKit

/// Parent bounds must be the aspect-fitted full image, excluding letterboxing.
struct CropOverlay: View {
    @Binding var region: CropRegion
    let sourceSize: CGSize
    let aspect: Double?
    @State private var dragOrigin: CropRegion?
    @State private var hoveredHandle: CropHandle?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let r = region.rect
            let box = CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
            ZStack(alignment: .topLeading) {
                Path { path in path.addRect(CGRect(origin: .zero, size: size)); path.addRect(box) }
                    .fill(Color.black.opacity(0.52), style: FillStyle(eoFill: true)).allowsHitTesting(false)
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .frame(width: box.width, height: box.height).position(x: box.midX, y: box.midY)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        if dragOrigin == nil { dragOrigin = region }
                        guard size.width > 0, size.height > 0 else { return }
                        region = (dragOrigin ?? region).moved(by: CGSize(width: value.translation.width / size.width, height: value.translation.height / size.height))
                    }.onEnded { _ in dragOrigin = nil })
                    .onHover { inside in if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() } }
                    .accessibilityLabel(L("裁切选框"))
                    .accessibilityValue(L("左侧 \(Int(r.minX * 100))%，顶部 \(Int(r.minY * 100))%，宽度 \(Int(r.width * 100))%，高度 \(Int(r.height * 100))%"))
                    .accessibilityHint(L("拖动以移动选框；四边和四角可调整大小"))
                    .accessibilityAction(named: Text(L("向左移动"))) { region = region.moved(by: CGSize(width: -0.01, height: 0)) }
                    .accessibilityAction(named: Text(L("向右移动"))) { region = region.moved(by: CGSize(width: 0.01, height: 0)) }
                    .accessibilityAction(named: Text(L("向上移动"))) { region = region.moved(by: CGSize(width: 0, height: -0.01)) }
                    .accessibilityAction(named: Text(L("向下移动"))) { region = region.moved(by: CGSize(width: 0, height: 0.01)) }
                Path { path in
                    path.addRect(box.insetBy(dx: 0.75, dy: 0.75))
                    for fraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
                        path.move(to: CGPoint(x: box.minX + box.width * fraction, y: box.minY)); path.addLine(to: CGPoint(x: box.minX + box.width * fraction, y: box.maxY))
                        path.move(to: CGPoint(x: box.minX, y: box.minY + box.height * fraction)); path.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height * fraction))
                    }
                }.stroke(.white.opacity(0.7), lineWidth: 1).shadow(color: .black.opacity(0.6), radius: 1).allowsHitTesting(false)
                ForEach(CropHandle.allCases) { handle in
                    let x = handle.horizontal < 0 ? box.minX : handle.horizontal > 0 ? box.maxX : box.midX
                    let y = handle.vertical < 0 ? box.minY : handle.vertical > 0 ? box.maxY : box.midY
                    Circle().fill(.white).overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1)).frame(width: 9, height: 9)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                        .position(x: min(size.width - 5, max(5, x)), y: min(size.height - 5, max(5, y)))
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            if dragOrigin == nil { dragOrigin = region }
                            guard size.width > 0, size.height > 0 else { return }
                            region = (dragOrigin ?? region).resized(handle: handle, translation: CGSize(width: value.translation.width / size.width, height: value.translation.height / size.height), sourceSize: sourceSize, aspect: aspect)
                        }.onEnded { _ in dragOrigin = nil })
                        .onHover { inside in
                            hoveredHandle = inside ? handle : nil
                            if inside { (handle.horizontal == 0 ? NSCursor.resizeUpDown : handle.vertical == 0 ? NSCursor.resizeLeftRight : NSCursor.crosshair).set() }
                            else { NSCursor.arrow.set() }
                        }
                        .accessibilityLabel(L("裁切" + handle.title))
                        .accessibilityHint(L("拖动调整大小"))
                        .accessibilityAdjustableAction { direction in
                            let delta: CGFloat = direction == .increment ? 0.01 : -0.01
                            region = region.resized(handle: handle, translation: CGSize(width: delta * CGFloat(handle.horizontal), height: delta * CGFloat(handle.vertical)), sourceSize: sourceSize, aspect: aspect)
                        }
                }
            }
        }
    }
}
