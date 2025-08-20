import Cocoa
import ApplicationServices

// ===================== Tuning =====================
fileprivate let MAX_HISTORY           = 32     // samples kept
fileprivate let IDLE_RESET_MS        = 100.0  // clear buffer after this idle
fileprivate let RATE_WINDOW_MS       = 100.0  // window to measure event rate
fileprivate let TRACKPAD_RATE_MIN    = 6      // >= events per RATE_WINDOW_MS → trackpad
fileprivate let SMALL_DELTA_LIMIT    = 15     // |point delta| < limit is "small"
fileprivate let SMALL_RATIO_REQ      = 0.60   // small/total ratio when rate is borderline
// =================================================

fileprivate struct ScrollSample {
    let t: CFTimeInterval
    let pdx: Int64
    let pdy: Int64
    let cont: Bool
}

fileprivate enum ScrollClass { case unknown, trackpadLike, wheelLike }

fileprivate final class ScrollClassifier {
    private var buf: [ScrollSample] = []
    private var lastTime: CFTimeInterval = 0
    private var current: ScrollClass = .unknown

    @inline(__always)
    private func ms(_ dt: CFTimeInterval) -> Double { dt * 1000.0 }

    private func reset(_ reason: String) {
        buf.removeAll(keepingCapacity: true)
        current = .unknown
        // print("[debug] reset: \(reason)")
    }

    func classify(_ e: CGEvent) -> ScrollClass {
        let now   = CFAbsoluteTimeGetCurrent()
        let pdx   = e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let pdy   = e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let cont  = e.getIntegerValueField(CGEventField(rawValue: 99)!) != 0  // kCGScrollWheelEventIsContinuous

        // Idle → reset
        if lastTime != 0 {
            let gap = ms(now - lastTime)
            if gap >= IDLE_RESET_MS { reset("idle gap \(Int(gap))ms") }
        }
        lastTime = now

        // Record sample
        buf.append(ScrollSample(t: now, pdx: pdx, pdy: pdy, cont: cont))
        if buf.count > MAX_HISTORY { buf.removeFirst() }

        // Hard signal: continuous => trackpad-like for this session
        if cont {
            if current != .trackpadLike {
                current = .trackpadLike
                // On state entry, start fresh to avoid contamination from prior mouse samples
                buf.removeAll(keepingCapacity: true)
            }
            return current
        }

        // Measure rate in last RATE_WINDOW_MS
        let cutoff = now - (RATE_WINDOW_MS / 1000.0)
        let recent = buf.filter { $0.t >= cutoff }
        let rate   = recent.count

        // Fast path by rate: dense streams are trackpad-like
        if rate >= TRACKPAD_RATE_MIN {
            if current != .trackpadLike {
                current = .trackpadLike
                buf.removeAll(keepingCapacity: true)
            }
            return current
        }

        // Borderline: look at "smallness" ratio within the recent window
        if !recent.isEmpty {
            let small = recent.filter { abs($0.pdx) < SMALL_DELTA_LIMIT && abs($0.pdy) < SMALL_DELTA_LIMIT }.count
            let ratio = Double(small) / Double(recent.count)

            // If stream is not dense and not continuous, prefer "wheel"
            // Only upgrade to trackpad if it's *very* small-like and non-bursty (rare)
            if ratio >= SMALL_RATIO_REQ && rate >= (TRACKPAD_RATE_MIN - 2) {
                if current != .trackpadLike {
                    current = .trackpadLike
                    buf.removeAll(keepingCapacity: true)
                }
                return current
            }
        }

        // Otherwise treat as wheel-like
        if current != .wheelLike {
            current = .wheelLike
            buf.removeAll(keepingCapacity: true)
        }
        return current
    }

    // Optional: allow external reset (e.g., when keybind toggles, etc.)
    func hardReset() { reset("external") }
}

fileprivate let classifier = ScrollClassifier()

@inline(__always)
fileprivate func invertScroll(_ event: CGEvent) {
    for field in [
        CGEventField.scrollWheelEventDeltaAxis1,
        .scrollWheelEventDeltaAxis2,
        .scrollWheelEventDeltaAxis3,
        .scrollWheelEventPointDeltaAxis1,
        .scrollWheelEventPointDeltaAxis2,
        .scrollWheelEventPointDeltaAxis3
    ] {
        let v = event.getIntegerValueField(field)
        if v != 0 { event.setIntegerValueField(field, value: -v) }
    }
}

// MARK: - Event Callback
func eventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    switch type {

    case .scrollWheel:
        let cls = classifier.classify(event)
        // Invert only for wheel-like
        if cls == .wheelLike { invertScroll(event) }
        return Unmanaged.passRetained(event)

    case .keyDown:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let ctrl = flags.contains(.maskControl)
        let shift = flags.contains(.maskShift)

        // Ctrl+Shift+S → Screenshot UI
        if ctrl && shift && keyCode == 1 {
            _ = Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-a", "Screenshot"])
            return nil
        }
        // Ctrl+\ → iTerm
        if ctrl && keyCode == 42 {
            _ = Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-a", "iTerm"])
            return nil
        }
        // Optional: Ctrl+Shift+R → reset classifier (handy while testing)
        if ctrl && shift && keyCode == 15 {
            classifier.hardReset()
            // fputs("[debug] classifier reset\n", stderr)
            return nil
        }
        return Unmanaged.passRetained(event)

    default:
        return Unmanaged.passRetained(event)
    }
}

// MARK: - Install the Event Tap
let mask = (1 << CGEventType.scrollWheel.rawValue) | (1 << CGEventType.keyDown.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(mask),
    callback: eventCallback,
    userInfo: nil
) else {
    fputs("Failed to create event tap. Grant Accessibility permissions in System Settings.\n", stderr)
    exit(1)
}

// MARK: - Run Loop Integration
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
