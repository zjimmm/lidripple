import Foundation
import Testing
@testable import lidripple_fidelity

@Test func artifactHashUsesLowercaseSHA256() {
    #expect(
        ArtifactHash.sha256(data: Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
}
