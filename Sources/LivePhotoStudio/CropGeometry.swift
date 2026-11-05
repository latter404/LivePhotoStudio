import Foundation

/// Coordinates refer to the displayed, already-rotated image, with a top-left origin.
struct CropRegion: Sendable, Equatable {
    var rect: CGRect
    static let full = CropRegion(rect: CGRect(x: 0, y: 0, width: 1, height: 1))

    init(rect: CGRect) {
        guard [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy({ $0.isFinite }), rect.width > 0, rect.height > 0 else {
            self.rect = CGRect(x: 0, y: 0, width: 1, height: 1); return
        }
        let x = min(1, max(0, rect.minX)), y = min(1, max(0, rect.minY))
        let right = min(1, max(0, rect.maxX)), bottom = min(1, max(0, rect.maxY))
        guard right > x, bottom > y else { self.rect = CGRect(x: 0, y: 0, width: 1, height: 1); return }
        self.rect = CGRect(x: x, y: y, width: right - x, height: bottom - y)
    }

    var isFull: Bool {
        let r = CropRegion(rect: rect).rect
        return abs(r.minX) < 0.000001 && abs(r.minY) < 0.000001 && abs(r.width - 1) < 0.000001 && abs(r.height - 1) < 0.000001
    }

    /// Round size independently from position so moving a crop never changes its output dimensions.
    func pixelRect(in size: CGSize) -> CGRect {
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1 else { return .zero }
        let r = CropRegion(rect: rect).rect, w = floor(size.width), h = floor(size.height)
        // Tolerate insignificant normalized-coordinate drift at exact half-pixel ties.
        let width = min(w, max(1, floor(r.width * w + 0.5 + 0.000000001)))
        let height = min(h, max(1, floor(r.height * h + 0.5 + 0.000000001)))
        let x = min(w - width, max(0, (r.minX * w).rounded()))
        let y = min(h - height, max(0, (r.minY * h).rounded()))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func moved(by translation: CGSize) -> CropRegion {
        guard translation.width.isFinite, translation.height.isFinite else { return CropRegion(rect: rect) }
        let r = CropRegion(rect: rect).rect
        return CropRegion(rect: CGRect(x: min(1 - r.width, max(0, r.minX + translation.width)),
                                       y: min(1 - r.height, max(0, r.minY + translation.height)), width: r.width, height: r.height))
    }

    func rotated(clockwise turns: Int) -> CropRegion {
        let r = CropRegion(rect: rect).rect
        switch (turns % 4 + 4) % 4 {
        case 1: return CropRegion(rect: CGRect(x: 1 - r.maxY, y: r.minX, width: r.height, height: r.width))
        case 2: return CropRegion(rect: CGRect(x: 1 - r.maxX, y: 1 - r.maxY, width: r.width, height: r.height))
        case 3: return CropRegion(rect: CGRect(x: r.minY, y: 1 - r.maxX, width: r.height, height: r.width))
        default: return CropRegion(rect: r)
        }
    }

    func resized(handle: CropHandle, translation: CGSize, sourceSize: CGSize, aspect: Double?) -> CropRegion {
        let r = CropRegion(rect: rect).rect
        guard translation.width.isFinite, translation.height.isFinite else { return CropRegion(rect: r) }
        let sw = sourceSize.width.isFinite && sourceSize.width > 0 ? sourceSize.width : 1
        let sh = sourceSize.height.isFinite && sourceSize.height > 0 ? sourceSize.height : 1
        let minW = min(0.04, max(0.01, 2 / sw)), minH = min(0.04, max(0.01, 2 / sh))
        let sx = CGFloat(handle.horizontal), sy = CGFloat(handle.vertical)
        guard let aspect, aspect.isFinite, aspect > 0 else {
            var left = r.minX, right = r.maxX, top = r.minY, bottom = r.maxY
            if sx < 0 { left = min(right - minW, max(0, left + translation.width)) }
            if sx > 0 { right = max(left + minW, min(1, right + translation.width)) }
            if sy < 0 { top = min(bottom - minH, max(0, top + translation.height)) }
            if sy > 0 { bottom = max(top + minH, min(1, bottom + translation.height)) }
            return CropRegion(rect: CGRect(x: left, y: top, width: right - left, height: bottom - top))
        }
        // Ratio in normalized coordinates; source pixels may be landscape or portrait.
        let ratio = CGFloat(aspect) * sh / sw
        guard ratio.isFinite, ratio > 0 else { return CropRegion(rect: r) }
        if sx != 0 && sy != 0 {
            let anchorX = sx > 0 ? r.minX : r.maxX, anchorY = sy > 0 ? r.minY : r.maxY
            let dx = translation.width * sx, dy = translation.height * sy
            let desiredW = abs(dx) / max(r.width, 0.00001) >= abs(dy) / max(r.height, 0.00001)
                ? r.width + dx : (r.height + dy) * ratio
            let limitW = min(sx > 0 ? 1 - anchorX : anchorX, (sy > 0 ? 1 - anchorY : anchorY) * ratio)
            let w = min(limitW, max(min(limitW, max(minW, minH * ratio)), desiredW)), h = w / ratio
            return CropRegion(rect: CGRect(x: sx > 0 ? anchorX : anchorX - w, y: sy > 0 ? anchorY : anchorY - h, width: w, height: h))
        }
        if sx != 0 {
            let anchorX = sx > 0 ? r.minX : r.maxX, cy = r.midY
            let limitW = min(sx > 0 ? 1 - anchorX : anchorX, 2 * min(cy, 1 - cy) * ratio)
            let w = min(limitW, max(min(limitW, max(minW, minH * ratio)), r.width + translation.width * sx)), h = w / ratio
            return CropRegion(rect: CGRect(x: sx > 0 ? anchorX : anchorX - w, y: cy - h / 2, width: w, height: h))
        }
        let anchorY = sy > 0 ? r.minY : r.maxY, cx = r.midX
        let limitH = min(sy > 0 ? 1 - anchorY : anchorY, 2 * min(cx, 1 - cx) / ratio)
        let h = min(limitH, max(min(limitH, max(minH, minW / ratio)), r.height + translation.height * sy)), w = h * ratio
        return CropRegion(rect: CGRect(x: cx - w / 2, y: sy > 0 ? anchorY : anchorY - h, width: w, height: h))
    }
}

enum CropHandle: String, CaseIterable, Identifiable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    var id: Self { self }
    var horizontal: Int { switch self { case .topLeft, .left, .bottomLeft: return -1; case .topRight, .right, .bottomRight: return 1; default: return 0 } }
    var vertical: Int { switch self { case .topLeft, .top, .topRight: return -1; case .bottomLeft, .bottom, .bottomRight: return 1; default: return 0 } }
    var title: String { switch self { case .topLeft: return "左上角"; case .top: return "上边"; case .topRight: return "右上角"; case .right: return "右边"; case .bottomRight: return "右下角"; case .bottom: return "下边"; case .bottomLeft: return "左下角"; case .left: return "左边" } }
}

enum CropPreset: String, CaseIterable, Identifiable {
    case off, free, original, square, landscape43, portrait34, landscape32, portrait23, landscape169, portrait916
    var id: Self { self }
    var title: String { switch self {
    case .off: return "不裁切"; case .free: return "自由"; case .original: return "原比例"; case .square: return "1:1"
    case .landscape43: return "4:3"; case .portrait34: return "3:4"; case .landscape32: return "3:2"; case .portrait23: return "2:3"
    case .landscape169: return "16:9"; case .portrait916: return "9:16"
    } }
    func aspect(in size: CGSize) -> Double? { switch self {
    case .off, .free: return nil
    case .original: return size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0 ? size.width / size.height : 1
    case .square: return 1; case .landscape43: return 4 / 3; case .portrait34: return 3 / 4
    case .landscape32: return 3 / 2; case .portrait23: return 2 / 3
    case .landscape169: return 16 / 9; case .portrait916: return 9 / 16
    } }
    func fittedRegion(in size: CGSize, center: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CropRegion {
        guard self != .off, let aspect = aspect(in: size), size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return .full }
        let ratio = aspect * size.height / size.width
        let w = min(1, ratio), h = min(1, 1 / ratio)
        let cx = center.x.isFinite ? center.x : 0.5, cy = center.y.isFinite ? center.y : 0.5
        return CropRegion(rect: CGRect(x: min(1 - w, max(0, cx - w / 2)), y: min(1 - h, max(0, cy - h / 2)), width: w, height: h))
    }
}
