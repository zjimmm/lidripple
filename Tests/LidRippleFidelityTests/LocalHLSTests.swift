import Foundation
import Testing
@testable import lidripple_fidelity

@Test func localHLSMaterializesInitMapAndFragmentsInPlaylistOrder() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("lidripple-hls-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let playlist = temporary.appendingPathComponent("reference.m3u8")
    try Data([1, 2]).write(to: temporary.appendingPathComponent("init.mp4"))
    try Data([3, 4]).write(to: temporary.appendingPathComponent("first.m4s"))
    try Data([5]).write(to: temporary.appendingPathComponent("second.m4s"))
    try """
    #EXTM3U
    #EXT-X-MAP:URI="init.mp4"
    #EXTINF:1.0,
    first.m4s
    #EXTINF:1.0,
    second.m4s
    #EXT-X-ENDLIST
    """.write(to: playlist, atomically: true, encoding: .utf8)

    let movie = try LocalHLS.materializeMovie(from: playlist)
    defer { try? FileManager.default.removeItem(at: movie) }

    #expect(try Data(contentsOf: movie) == Data([1, 2, 3, 4, 5]))
}
