import Testing
import Foundation
@testable import LidRippleCore

@Test func angleSampleStoresDegreesAndTimestamp() {
    let sample = AngleSample(degrees: 92.5, timestamp: 1.25)
    #expect(sample.degrees == 92.5)
    #expect(sample.timestamp == 1.25)
}

@Test func angleSamplesWithIdenticalValuesAreEqual() {
    #expect(AngleSample(degrees: 90, timestamp: 0) == AngleSample(degrees: 90, timestamp: 0))
    #expect(AngleSample(degrees: 90, timestamp: 0) != AngleSample(degrees: 91, timestamp: 0))
}
