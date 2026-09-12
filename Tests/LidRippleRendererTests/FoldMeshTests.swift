import Testing
@testable import LidRippleRenderer

@Test func defaultMeshHasSpecifiedTessellation() throws {
    let mesh = try FoldMesh.make()

    #expect(mesh.vertices.count == 17 * 65)
    #expect(mesh.indices.count == 16 * 64 * 6)
}

@Test func meshCornersUseBottomHingeCoordinates() throws {
    let mesh = try FoldMesh.make(columns: 2, rows: 2)

    #expect(mesh.vertices[0].position == SIMD2<Float>(-1, -1))
    #expect(mesh.vertices[0].textureCoordinate == SIMD2<Float>(0, 1))
    #expect(mesh.vertices[2].position == SIMD2<Float>(1, -1))
    #expect(mesh.vertices[2].textureCoordinate == SIMD2<Float>(1, 1))
    #expect(mesh.vertices[6].position == SIMD2<Float>(-1, 1))
    #expect(mesh.vertices[6].textureCoordinate == SIMD2<Float>(0, 0))
    #expect(mesh.vertices[8].position == SIMD2<Float>(1, 1))
    #expect(mesh.vertices[8].textureCoordinate == SIMD2<Float>(1, 0))
}

@Test func meshIndicesAreInBoundsAndCounterClockwise() throws {
    let mesh = try FoldMesh.make(columns: 4, rows: 3)

    for index in mesh.indices {
        #expect(Int(index) < mesh.vertices.count)
    }

    for triangleStart in stride(from: 0, to: mesh.indices.count, by: 3) {
        let a = mesh.vertices[Int(mesh.indices[triangleStart])].position
        let b = mesh.vertices[Int(mesh.indices[triangleStart + 1])].position
        let c = mesh.vertices[Int(mesh.indices[triangleStart + 2])].position
        let signedArea = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        #expect(signedArea > 0)
    }
}

@Test func adjacentCellsShareVerticesRatherThanDuplicatingThem() throws {
    let mesh = try FoldMesh.make(columns: 2, rows: 1)

    #expect(mesh.vertices.count == 6)
    #expect(mesh.indices == [0, 1, 3, 3, 1, 4, 1, 2, 4, 4, 2, 5])
}

@Test func zeroSizedMeshIsRejected() {
    #expect(throws: FoldMeshError.invalidGrid(columns: 0, rows: 64)) {
        try FoldMesh.make(columns: 0, rows: 64)
    }
    #expect(throws: FoldMeshError.invalidGrid(columns: 16, rows: 0)) {
        try FoldMesh.make(columns: 16, rows: 0)
    }
}
