import Cocoa
import Foundation

final class GlobalTimingLogger {
    private let outURL: URL
    private let idleGapThresholdMs: Double
    private let sourceLabel: String

    private let startedAt = CFAbsoluteTimeGetCurrent()
    private var lastEventMs: Double?
    private var openDown: [CGKeyCode: Double] = [:]

    private var fileHandle: FileHandle?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(outURL: URL, idleGapThresholdMs: Double, sourceLabel: String = "global_event_tap") {
        self.outURL = outURL
        self.idleGapThresholdMs = idleGapThresholdMs
        self.sourceLabel = sourceLabel
    }

    private func tMs() -> Double {
        (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0
    }

    func start() throws {
        try prepareFile()
        try writeHeader()
        try installTap()
        NSLog("GlobalTimingLogger: started -> %@", outURL.path)
    }

    func stop() {
        writeEvent(TimingEvent(
            kind: .sessionStop,
            tMs: tMs(),
            category: .unknown,
            subCategory: nil,
            keyCode: nil,
            modifiers: nil,
            autoRepeat: nil,
            dwellMs: nil,
            gapMs: nil,
            source: sourceLabel
        ))
        if let tap { CFMachPortInvalidate(tap) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        runLoopSource = nil
        tap = nil

        try? fileHandle?.close()
        fileHandle = nil
    }

    private func prepareFile() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: outURL.path) {
            fm.createFile(atPath: outURL.path, contents: nil)
        }
        fileHandle = try FileHandle(forWritingTo: outURL)
        try fileHandle?.seekToEnd()
    }

    private func writeHeader() throws {
        let header = TimingSessionHeader(
            kind: .sessionStart,
            startedAtISO8601: isoNow(),
            machine: hostname(),
            version: "motordna-global-v2",
            idleGapThresholdMs: idleGapThresholdMs,
            captureContent: false,
            notes: [
                "No typed text or key labels saved.",
                "Stores timing + coarse key category/subcategory only.",
                "Designed for personal telemetry and calibration."
            ]
        )
        let enc = JSONEncoder()
        let data = try enc.encode(header)
        fileHandle?.write(data)
        fileHandle?.write("\n".data(using: .utf8)!)
    }

    private func writeEvent(_ event: TimingEvent) {
        guard let fh = fileHandle else { return }
        do {
            let data = try JSONEncoder().encode(event)
            fh.write(data)
            fh.write("\n".data(using: .utf8)!)
        } catch {
            NSLog("GlobalTimingLogger: encode/write error %@", error.localizedDescription)
        }
    }

    private func installTap() throws {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let logger = Unmanaged<GlobalTimingLogger>.fromOpaque(refcon).takeUnretainedValue()
            return logger.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: refcon
        ) else {
            throw NSError(domain: "GlobalTimingLogger", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create event tap. Enable Accessibility permissions."])
        }

        self.tap = tap
        guard let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw NSError(domain: "GlobalTimingLogger", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create runloop source"])
        }
        self.runLoopSource = src

        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let now = tMs()
        if let last = lastEventMs {
            let gap = now - last
            if gap > idleGapThresholdMs {
                writeEvent(TimingEvent(
                    kind: .idleGap,
                    tMs: now,
                    category: .idle,
                    subCategory: "idle_gap",
                    keyCode: nil,
                    modifiers: nil,
                    autoRepeat: nil,
                    dwellMs: nil,
                    gapMs: gap,
                    source: sourceLabel
                ))
            }
        }
        lastEventMs = now

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let category = keyCategory(for: keyCode, flags: event.flags)
        let subCategory = keySubCategory(for: keyCode, flags: event.flags)
        let mods = normalizedModifiers(flags: event.flags)
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        switch type {
        case .keyDown:
            // Preserve initial keyDown for true dwell; don't overwrite on auto-repeat.
            if openDown[keyCode] == nil {
                openDown[keyCode] = now
            }
            writeEvent(TimingEvent(
                kind: .down,
                tMs: now,
                category: category,
                subCategory: subCategory,
                keyCode: Int(keyCode),
                modifiers: mods.isEmpty ? nil : mods,
                autoRepeat: isAutoRepeat ? true : nil,
                dwellMs: nil,
                gapMs: nil,
                source: sourceLabel
            ))

        case .keyUp:
            let dwell = openDown[keyCode].map { now - $0 }
            openDown.removeValue(forKey: keyCode)
            writeEvent(TimingEvent(
                kind: .up,
                tMs: now,
                category: category,
                subCategory: subCategory,
                keyCode: Int(keyCode),
                modifiers: mods.isEmpty ? nil : mods,
                autoRepeat: nil,
                dwellMs: dwell,
                gapMs: nil,
                source: sourceLabel
            ))

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }
}

struct GlobalLoggerArgs {
    var outPath: String = FileManager.default.currentDirectoryPath + "/HumanPaste/research/global_timing_log.ndjson"
    var idleGapMs: Double = 2000
}

func parseGlobalArgs() -> GlobalLoggerArgs {
    var args = GlobalLoggerArgs()
    var i = 1
    while i < CommandLine.arguments.count {
        let token = CommandLine.arguments[i]
        if token == "--out", i + 1 < CommandLine.arguments.count {
            args.outPath = CommandLine.arguments[i + 1]
            i += 2
            continue
        }
        if token == "--idle-gap-ms", i + 1 < CommandLine.arguments.count {
            args.idleGapMs = Double(CommandLine.arguments[i + 1]) ?? args.idleGapMs
            i += 2
            continue
        }
        i += 1
    }
    return args
}

@main
struct GlobalTimingLoggerMain {
    static func main() {
        let args = parseGlobalArgs()
        let logger = GlobalTimingLogger(outURL: URL(fileURLWithPath: args.outPath), idleGapThresholdMs: args.idleGapMs)

        do {
            try logger.start()
        } catch {
            fputs("GlobalTimingLogger start failed: \(error.localizedDescription)\n", stderr)
            exit(2)
        }

        signal(SIGINT) { _ in
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        signal(SIGTERM) { _ in
            CFRunLoopStop(CFRunLoopGetCurrent())
        }

        CFRunLoopRun()
        logger.stop()
    }
}
