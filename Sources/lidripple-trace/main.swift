import Foundation
import LidRippleCore
import LidRippleSensor

let report = SensorProbe.probe()
print(report.description)
guard report.isPresent else { exit(0) }

let source = HIDAngleSource()
try source.start { sample in
    print(String(format: "%8.2f deg  t=%.3f", sample.degrees, sample.timestamp))
}
print("Polling at 60 Hz. Move the lid. Ctrl-C to stop.")
RunLoop.main.run()
