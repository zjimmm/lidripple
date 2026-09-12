public enum FoldMeshError: Error, Equatable {
    case invalidGrid(columns: Int, rows: Int)
}

/// A regular, indexed screen mesh whose normalized `v` coordinate starts at
/// the physical hinge (the bottom edge) and ends at the top of the panel.
public struct FoldMesh: Equatable, Sendable {
    public struct Vertex: Equatable, Sendable {
        public let position: SIMD2<Float>
        public let textureCoordinate: SIMD2<Float>

        public init(position: SIMD2<Float>, textureCoordinate: SIMD2<Float>) {
            self.position = position
            self.textureCoordinate = textureCoordinate
        }
    }

    public let vertices: [Vertex]
    public let indices: [UInt32]

    public static func make(columns: Int = 16, rows: Int = 64) throws -> FoldMesh {
        guard columns > 0, rows > 0 else {
            throw FoldMeshError.invalidGrid(columns: columns, rows: rows)
        }

        var vertices: [Vertex] = []
        vertices.reserveCapacity((columns + 1) * (rows + 1))

        for row in 0...rows {
            let v = Float(row) / Float(rows)
            for column in 0...columns {
                let u = Float(column) / Float(columns)
                vertices.append(
                    Vertex(
                        position: SIMD2<Float>(u * 2 - 1, v * 2 - 1),
                        textureCoordinate: SIMD2<Float>(u, 1 - v)
                    )
                )
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(columns * rows * 6)
        let stride = columns + 1

        for row in 0..<rows {
            for column in 0..<columns {
                let bottomLeft = UInt32(row * stride + column)
                let bottomRight = bottomLeft + 1
                let topLeft = bottomLeft + UInt32(stride)
                let topRight = topLeft + 1

                indices.append(contentsOf: [
                    bottomLeft, bottomRight, topLeft,
                    topLeft, bottomRight, topRight,
                ])
            }
        }

        return FoldMesh(vertices: vertices, indices: indices)
    }
}
