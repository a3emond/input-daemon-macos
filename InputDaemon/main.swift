import Cocoa
import ApplicationServices

// MARK: - Distinguish Trackpad vs Mouse
//
// macOS delivers scroll events through CGEvent. Unfortunately, the "is trackpad or not"
// info is not exposed in the public enum. Instead, we use raw HID field codes:
//
// 22  -> kCGScrollWheelEventPhase (0 = none, non-zero means gesture phase info is present)
// 23  -> kCGScrollWheelEventMomentumPhase (0 = none, non-zero means inertia/momentum scrolling)
// 99  -> kCGScrollWheelEventIsContinuous (1 for continuous pixel deltas, typical of trackpads)
//
// Trackpads: usually continuous, with phase/momentum values.
// Mice: usually line-based, no phase/momentum.
//
func isTrackpad(_ event: CGEvent) -> Bool {
    let kCGScrollWheelEventIsContinuous: UInt32 = 99
    let kCGScrollWheelEventPhase: UInt32 = 22
    let kCGScrollWheelEventMomentumPhase: UInt32 = 23

    let isContinuous = event.getIntegerValueField(CGEventField(rawValue: kCGScrollWheelEventIsContinuous)!) != 0
    let phase = event.getIntegerValueField(CGEventField(rawValue: kCGScrollWheelEventPhase)!)
    let momentum = event.getIntegerValueField(CGEventField(rawValue: kCGScrollWheelEventMomentumPhase)!)

    return isContinuous || phase != 0 || momentum != 0
}

// MARK: - Event Callback
//
// Every event captured by our "event tap" passes through this function.
// We check the event type and decide how to handle it.
//
func eventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    switch type {

    // --- Handle Scroll Events ---
    case .scrollWheel:
        // Flip direction only if the device is *not* a trackpad
        if !isTrackpad(event) {
            for field in [
                CGEventField.scrollWheelEventDeltaAxis1,   // vertical lines
                .scrollWheelEventDeltaAxis2,               // horizontal lines
                .scrollWheelEventDeltaAxis3,               // depth (rarely used)
                .scrollWheelEventPointDeltaAxis1,          // vertical pixels
                .scrollWheelEventPointDeltaAxis2,          // horizontal pixels
                .scrollWheelEventPointDeltaAxis3           // depth pixels
            ] {
                let v = event.getIntegerValueField(field)
                if v != 0 {
                    event.setIntegerValueField(field, value: -v) // invert direction
                }
            }
        }
        // Returning the event lets it continue to the system/app
        return Unmanaged.passRetained(event)

    // --- Handle KeyDown Events ---
    case .keyDown:
        // macOS key codes: 's' key = 1
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let isS = (keyCode == 1)
        let ctrl = flags.contains(.maskControl)
        let shift = flags.contains(.maskShift)

        // If Ctrl+Shift+S pressed...
        if isS && ctrl && shift {
            // Launch the Screenshot.app (same as Cmd+Shift+5 UI)
            _ = Process.launchedProcess(
                launchPath: "/usr/bin/open",
                arguments: ["-a", "Screenshot"]
            )
            // Returning nil means "don’t pass this event forward"
            return nil
        }
        return Unmanaged.passRetained(event)

    // --- Everything Else ---
    default:
        return Unmanaged.passRetained(event)
    }
}

// MARK: - Install the Event Tap
//
// A "CGEventTap" lets us intercept low-level system events before they
// reach apps. We ask to listen for scrollWheel + keyDown events.
//
let mask = (1 << CGEventType.scrollWheel.rawValue) | (1 << CGEventType.keyDown.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cghidEventTap,         // Listen at HID system level
    place: .headInsertEventTap,  // Insert at the head of the stream
    options: .defaultTap,        // Active (not passive observer)
    eventsOfInterest: CGEventMask(mask),
    callback: eventCallback,
    userInfo: nil
) else {
    fputs("Failed to create event tap. Grant Accessibility permissions in System Settings.\n", stderr)
    exit(1)
}

// MARK: - Run Loop Integration
//
// Event taps produce Mach messages. We wrap them in a CFRunLoopSource,
// add them to the main run loop, and start the loop so our callback runs.
//
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
