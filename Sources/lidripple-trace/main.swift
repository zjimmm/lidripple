import Foundation
import LidRippleCore
import LidRippleSensor
import LidRippleTrace

let usage = """
lidripple-trace — lid angle sensor tool

USAGE:
  lidripple-trace probe
  lidripple-trace record [--name NAME] [--out PATH]
  lidripple-trace replay PATH
  lidripple-trace info PATH

  probe    Report whether this Mac has a lid angle sensor, then stream angles.
  record   Stream angles and write a trace JSON on Ctrl-C.
  replay   Replay a trace file through FoldDriver and print fold state.
  info     Summarize a trace file.
"""

func value(for flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func deviceModel() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var bytes = [UInt8](repeating: 0, count: size)
    sysctlbyname("hw.model", &bytes, &size, nil, 0)
    if let nul = bytes.firstIndex(of: 0) {
        bytes.removeSubrange(nul...)
    }
    return String(decoding: bytes, as: UTF8.self)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(1)
}

switch command {
case "probe":
    let report = SensorProbe.probe()
    print(report.description)
    guard report.isPresent else { exit(0) }
    let source = HIDAngleSource()
    try source.start { sample in
        print(String(format: "%8.2f deg  t=%.3f", sample.degrees, sample.timestamp))
    }
    print("Polling at 60 Hz. Move the lid. Ctrl-C to stop.")
    RunLoop.main.run()

case "record":
    let name = value(for: "--name", in: args) ?? "untitled"
    let out = value(for: "--out", in: args) ?? "\(name).json"
    let source = HIDAngleSource()
    guard source.isAvailable else {
        print("No lid angle sensor on this Mac; nothing to record.")
        exit(1)
    }
    let recorder = TraceRecorder(name: name, deviceModel: deviceModel())

    // Write the trace on Ctrl-C rather than losing it.
    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signalSource.setEventHandler {
        source.stop()
        let trace = recorder.finish()
        do {
            try trace.encoded().write(to: URL(fileURLWithPath: out))
            print("\nWrote \(trace.samples.count) samples to \(out)")
            exit(0)
        } catch {
            print("\nFailed to write \(out): \(error)")
            exit(1)
        }
    }
    signalSource.resume()
    signal(SIGINT, SIG_IGN)

    try source.start { recorder.record($0) }
    print("Recording '\(name)' at 60 Hz. Move the lid, then Ctrl-C to save.")
    RunLoop.main.run()

case "replay":
    guard args.count > 1 else { print(usage); exit(1) }
    let trace = try Trace.decoded(from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    let driver = FoldDriver()
    print("phase        progress  angle")
    for sample in trace.angleSamples {
        let state = driver.ingest(sample)
        let phase = state.phase.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)
        print(phase + String(format: "  %7.4f  %6.2f", state.progress, sample.degrees))
    }

case "info":
    guard args.count > 1 else { print(usage); exit(1) }
    let trace = try Trace.decoded(from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    let angles = trace.samples.map(\.deg)
    let duration = (trace.samples.last?.t ?? 0) - (trace.samples.first?.t ?? 0)
    print("""
    name:     \(trace.name)
    device:   \(trace.deviceModel)
    recorded: \(trace.recordedAt)
    samples:  \(trace.samples.count)
    duration: \(String(format: "%.3f", duration)) s
    angles:   \(String(format: "%.2f", angles.min() ?? 0)) to \(String(format: "%.2f", angles.max() ?? 0)) deg
    """)

default:
    print(usage)
    exit(1)
}
