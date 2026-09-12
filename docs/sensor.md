# Lid angle sensor hardware notes

This documents the hardware investigation behind `LidRippleSensor`
(`HIDAngleSource` and `SensorProbe`): what the sensor is, why matching and
reading it takes the specific shape it does in this codebase, and what is
still unconfirmed. It exists because the original investigation notes lived
in `.superpowers/sdd/`, which is gitignored and never reaches the repository
— the two source comments that used to point there now point here instead.

## The hardware

The internal lid angle sensor on recent MacBooks is exposed as an `IOHIDDevice`
with Apple's vendor ID `0x05AC` and product ID `0x8104`, HID sensor page
`0x0020`, usage `0x008A` (orientation). Physically, it is a MagAlpha ma981
magnetic rotary angle sensor sitting on Apple's Sensor Platform Unit (SPU) —
the same subsystem that exposes the accelerometer, gyroscope, and various
temperature sensors as sibling HID devices.

## Why vendor/product ID alone isn't enough

On Apple Silicon Macs, multiple physically distinct HID sub-devices on the SPU
— the accelerometer, gyroscope, this angle sensor, temperature sensors, and
others — share the *same* vendor ID and product ID. Matching on those two
values alone can return several candidate devices, not just the lid sensor.

Adding `"UsagePage"` / `"Usage"` to the `IOHIDManagerSetDeviceMatching`
criteria narrows the match considerably, but empirically still isn't a
guaranteed unique match on this hardware (`SensorProbe.matchingDevices()` can
still return more than one candidate). Two notes on those matching keys
specifically:

- They are the bare string keys `"UsagePage"` / `"Usage"` (i.e.
  `kIOHIDElementUsagePageKey` / `kIOHIDElementUsageKey`), **not**
  `kIOHIDDeviceUsagePageKey` / `kIOHIDDeviceUsageKey` (`"DeviceUsagePage"` /
  `"DeviceUsage"`). `IOHIDManagerSetDeviceMatching` accepts the bare
  element-level keys for device-level filtering too — undocumented, but this
  is what was empirically validated against real Mac16,12 hardware, and it
  matches the approach used by the reference implementation
  (`github.com/samhenrigold/LidAngleSensor`). The device-prefixed keys may
  also work; they were not what was tested, so this codebase deliberately
  keeps the bare keys rather than "correcting" them.
- Because even this narrowed match isn't guaranteed unique, `HIDAngleSource.start()`
  goes one step further: it iterates every candidate device returned by
  `SensorProbe.matchingDevices()`, opens each one, and validates it by
  actually requesting a report from it — keeping the first candidate that
  responds successfully and closing the rest.

## Why a Feature report instead of an Input element

The usage-page/usage match resolves to a wrapping HID *Collection* element on
this hardware, not a scalar Input element. Calling `IOHIDDeviceGetValue` on a
Collection always fails (`kIOReturnBadArgument`), which is why this codebase
doesn't use the `IOHIDDeviceCopyMatchingElements` / `IOHIDDeviceGetValue` path
at all.

Instead, reading works via `IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature,
reportID: 1, &buffer, &length)` into an 8-byte buffer, then parsing a
little-endian `UInt16` out of bytes 1–2 of that buffer. This mirrors the
approach in the reference implementation cited by the spec
(`github.com/samhenrigold/LidAngleSensor`).

## The raw-to-degrees scale factor

The shipped code uses `rawToDegrees = 1.0` (unscaled) — i.e. it treats the raw
`UInt16` as whole degrees directly (1 LSB = 1°). This was not the original
assumption: reference implementations describe 0.01° precision (a scaled
16-bit value), and the spec originally stated that.

The scale was cross-checked against macOS's own clamshell state on the actual
test hardware (Mac16,12). With `ioreg -r -k AppleClamshellState` reporting
`AppleClamshellState = No` (lid physically open) held steady, the sensor
reported raw value `0x0063` = 99 consistently over 300 samples. An open lid
cannot be at 0.99°, so the 0.01°-per-LSB scale is ruled out, and the unscaled
1°-per-LSB mapping is corroborated by this reading (99° is a plausible open
angle).

**This is not yet confirmed.** A full physical sweep — closed, and several
known angles in between — has NOT been done, and doing it requires a human
physically moving the lid while watching the sensor output. This is
outstanding work and should be treated as a priority for whoever next touches
sensor tuning, before leaning on `rawToDegrees = 1.0` for anything precision
sensitive.

## Permissions

No Input Monitoring permission was required to open or read this device
across all testing done so far. Spec §11/§15 names Input Monitoring as a
possible risk for HID access in general; that risk did not manifest for this
device class in practice, though this has only been observed on one machine
(Mac16,12) and OS version, not verified broadly.
