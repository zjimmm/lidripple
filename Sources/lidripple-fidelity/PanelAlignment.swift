import Foundation

struct AlignmentPoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

struct PanelAlignment: Codable, Equatable, Sendable {
    struct Corners: Codable, Equatable, Sendable {
        let topLeft: AlignmentPoint
        let topRight: AlignmentPoint
        let bottomRight: AlignmentPoint
        let bottomLeft: AlignmentPoint
    }

    let outputWidth: Int
    let outputHeight: Int
    let displayCorners: Corners
    /// Polygons in normalized corrected-panel coordinates. Pixels inside them
    /// are excluded from measurements, but remain visible in comparison media.
    let exclusionPolygons: [[AlignmentPoint]]

    func validate(sourceWidth: Int? = nil, sourceHeight: Int? = nil) throws {
        guard outputWidth > 1, outputHeight > 1 else {
            throw FidelityError.invalidReferenceManifest("alignment output dimensions must exceed one pixel")
        }
        let corners = [
            displayCorners.topLeft,
            displayCorners.topRight,
            displayCorners.bottomRight,
            displayCorners.bottomLeft,
        ]
        guard corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw FidelityError.invalidReferenceManifest("display corners must be finite")
        }
        if let sourceWidth, let sourceHeight {
            guard corners.allSatisfy({
                $0.x >= 0 && $0.x <= Double(sourceWidth - 1)
                    && $0.y >= 0 && $0.y <= Double(sourceHeight - 1)
            }) else {
                throw FidelityError.invalidReferenceManifest("display corners fall outside the source frame")
            }
        }
        let area = zip(corners, corners.dropFirst() + [corners[0]]).reduce(0.0) {
            $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y
        }
        guard abs(area) > 1 else {
            throw FidelityError.invalidReferenceManifest("display corners are degenerate")
        }
        for polygon in exclusionPolygons {
            guard polygon.count >= 3,
                  polygon.allSatisfy({
                      $0.x.isFinite && $0.y.isFinite
                          && (0...1).contains($0.x) && (0...1).contains($0.y)
                  }) else {
                throw FidelityError.invalidReferenceManifest("exclusion polygons must contain normalized points")
            }
        }
    }

    func correct(_ frame: PixelFrame) throws -> PixelFrame {
        try validate(sourceWidth: frame.width, sourceHeight: frame.height)
        let transform = try ProjectiveMap(corners: displayCorners)
        var output = [UInt8](repeating: 0, count: outputWidth * outputHeight * 4)
        for y in 0..<outputHeight {
            let v = Double(y) / Double(outputHeight - 1)
            for x in 0..<outputWidth {
                let u = Double(x) / Double(outputWidth - 1)
                let source = transform.source(u: u, v: v)
                let pixel = frame.bilinearPixel(x: source.x, y: source.y)
                let offset = (y * outputWidth + x) * 4
                output.replaceSubrange(offset..<(offset + 4), with: pixel)
            }
        }
        return try PixelFrame(width: outputWidth, height: outputHeight, bytes: output)
    }

    func measurementMask() -> PixelMask {
        var included = [Bool](repeating: true, count: outputWidth * outputHeight)
        for y in 0..<outputHeight {
            let normalizedY = Double(y) / Double(outputHeight - 1)
            for x in 0..<outputWidth {
                let normalizedX = Double(x) / Double(outputWidth - 1)
                if exclusionPolygons.contains(where: {
                    Self.contains(AlignmentPoint(x: normalizedX, y: normalizedY), polygon: $0)
                }) {
                    included[y * outputWidth + x] = false
                }
            }
        }
        return PixelMask(width: outputWidth, height: outputHeight, included: included)
    }

    private static func contains(_ point: AlignmentPoint, polygon: [AlignmentPoint]) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for current in polygon.indices {
            let a = polygon[current]
            let b = polygon[previous]
            if (a.y > point.y) != (b.y > point.y) {
                let crossingX = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if point.x < crossingX { inside.toggle() }
            }
            previous = current
        }
        return inside
    }
}

struct PixelMask: Equatable, Sendable {
    let width: Int
    let height: Int
    let included: [Bool]

    static func all(width: Int, height: Int) -> PixelMask {
        PixelMask(width: width, height: height, included: [Bool](repeating: true, count: width * height))
    }

    func contains(x: Int, y: Int) -> Bool {
        x >= 0 && x < width && y >= 0 && y < height && included[y * width + x]
    }
}

private struct ProjectiveMap {
    let a: Double
    let b: Double
    let c: Double
    let d: Double
    let e: Double
    let f: Double
    let g: Double
    let h: Double

    init(corners: PanelAlignment.Corners) throws {
        let p0 = corners.topLeft
        let p1 = corners.topRight
        let p2 = corners.bottomRight
        let p3 = corners.bottomLeft
        let dx1 = p1.x - p2.x
        let dx2 = p3.x - p2.x
        let dx3 = p0.x - p1.x + p2.x - p3.x
        let dy1 = p1.y - p2.y
        let dy2 = p3.y - p2.y
        let dy3 = p0.y - p1.y + p2.y - p3.y
        let denominator = dx1 * dy2 - dx2 * dy1
        guard abs(denominator) > 1e-12 else {
            throw FidelityError.invalidReferenceManifest("display-corner transform is singular")
        }
        g = (dx3 * dy2 - dx2 * dy3) / denominator
        h = (dx1 * dy3 - dx3 * dy1) / denominator
        a = p1.x - p0.x + g * p1.x
        b = p3.x - p0.x + h * p3.x
        c = p0.x
        d = p1.y - p0.y + g * p1.y
        e = p3.y - p0.y + h * p3.y
        f = p0.y
    }

    func source(u: Double, v: Double) -> AlignmentPoint {
        let denominator = g * u + h * v + 1
        return AlignmentPoint(
            x: (a * u + b * v + c) / denominator,
            y: (d * u + e * v + f) / denominator
        )
    }
}

private extension PixelFrame {
    func bilinearPixel(x: Double, y: Double) -> [UInt8] {
        let clampedX = min(max(x, 0), Double(width - 1))
        let clampedY = min(max(y, 0), Double(height - 1))
        let x0 = Int(clampedX.rounded(.down))
        let y0 = Int(clampedY.rounded(.down))
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = clampedX - Double(x0)
        let ty = clampedY - Double(y0)

        return (0..<4).map { channel in
            func value(_ px: Int, _ py: Int) -> Double {
                Double(bytes[(py * width + px) * 4 + channel])
            }
            let top = value(x0, y0) * (1 - tx) + value(x1, y0) * tx
            let bottom = value(x0, y1) * (1 - tx) + value(x1, y1) * tx
            return UInt8(min(max((top * (1 - ty) + bottom * ty).rounded(), 0), 255))
        }
    }
}
