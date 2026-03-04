import Cocoa
import Carbon
import SwiftUI
import Combine

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var typer = HumanTyper()
    var eventTap: CFMachPort?
    var settingsWindow: NSWindow?
    var settingsModel = SettingsModel()
    var cancellables = Set<AnyCancellable>()

    // Sync guard to prevent feedback loops between SwiftUI model and AppDelegate state
    private var isSyncing = false

    // Config state
    var wpm: Int = 80
    var pausePct: Int = 15
    var typoPct: Int = 50
    var flightCapMs: Int = 700
    var thinkCapMs: Int = 600
    var initialDelayMs: Int = 200
    var correctionSpeed: Int = 100
    var burstWords: Int = 5
    var uncertaintyEnabled: Bool = true
    var falseStartMax: Int = 2
    var cursorEditMax: Int = 1
    var openaiApiKey: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("HumanPaste: init")

        // Load .env from app bundle's parent dir
        loadDotEnv()

        // Wire model callbacks
        settingsModel.applyCallback = { [weak self] in
            self?.syncFromModel()
        }
        settingsModel.testCallback = { [weak self] in
            self?.testTyping()
        }

        // Wire live log callback
        typer.logCallback = { [weak self] msg in
            if headlessMode {
                self?.settingsModel.appendLog(msg)
            } else {
                DispatchQueue.main.async {
                    self?.settingsModel.appendLog(msg)
                }
            }
        }

        // Observe verbose toggle changes
        settingsModel.$verboseLog.sink { [weak self] val in
            self?.typer.verboseLog = val
        }.store(in: &cancellables)

        applyAll()
        setupMenuBar()
        setupGlobalHotkey()
        prepareSettingsWindow()
    }

    // MARK: - Model Sync

    func syncFromModel() {
        guard !isSyncing else { return }
        isSyncing = true
        wpm = Int(settingsModel.wpm)
        pausePct = Int(settingsModel.pausePct)
        typoPct = Int(settingsModel.typoPct)
        flightCapMs = Int(settingsModel.flightCapMs)
        thinkCapMs = Int(settingsModel.thinkCapMs)
        initialDelayMs = Int(settingsModel.initialDelayMs)
        correctionSpeed = Int(settingsModel.correctionSpeed)
        burstWords = Int(settingsModel.burstWords)
        uncertaintyEnabled = settingsModel.uncertaintyEnabled
        falseStartMax = Int(settingsModel.falseStartMax)
        cursorEditMax = Int(settingsModel.cursorEditMax)
        openaiApiKey = settingsModel.openaiApiKey
        applyAll()
        isSyncing = false
    }

    func syncToModel() {
        guard !isSyncing else { return }
        isSyncing = true
        settingsModel.wpm = Double(wpm)
        settingsModel.pausePct = Double(pausePct)
        settingsModel.typoPct = Double(typoPct)
        settingsModel.flightCapMs = Double(flightCapMs)
        settingsModel.thinkCapMs = Double(thinkCapMs)
        settingsModel.initialDelayMs = Double(initialDelayMs)
        settingsModel.correctionSpeed = Double(correctionSpeed)
        settingsModel.burstWords = Double(burstWords)
        settingsModel.uncertaintyEnabled = uncertaintyEnabled
        settingsModel.falseStartMax = Double(falseStartMax)
        settingsModel.cursorEditMax = Double(cursorEditMax)
        settingsModel.openaiApiKey = openaiApiKey
        isSyncing = false
    }

    func applyAll() {
        typer.targetWPM = wpm
        typer.speedProfile = speedProfileForWPM(wpm, pausePct: pausePct, typoPct: typoPct)
        typer.pauseConfig = pauseConfigFromPercent(pausePct)
        typer.typoMultiplier = typoMultiplierFromPercent(typoPct)
        typer.typoProfile = typoProfiles["normal"]!
        typer.flightCapMs = Double(flightCapMs)
        typer.thinkCapMs = Double(thinkCapMs)
        typer.correctionSpeedPct = correctionSpeed
        typer.burstWords = burstWords
        typer.uncertaintyEnabled = uncertaintyEnabled
        // Scale trigger frequency with requested count — more false starts = tighter triggers
        let fsTriggerMin = max(8, 25 - falseStartMax * 2)
        let fsTriggerMax = max(15, 50 - falseStartMax * 3)
        let ceTriggerMin = max(12, 35 - cursorEditMax * 3)
        let ceTriggerMax = max(20, 60 - cursorEditMax * 5)
        let cooldown = max(4, 12 - falseStartMax)

        let hasKey = !openaiApiKey.isEmpty || !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "").isEmpty
        typer.openaiApiKey = openaiApiKey
        typer.uncertaintyConfig = UncertaintyConfig(
            enabled: uncertaintyEnabled,
            mode: "safe",
            predictionProvider: hasKey ? "openai" : "deterministic",
            openAIModel: "gpt-4.1-nano",
            openAITimeoutMs: 3000,
            planWindowWords: 3,
            minWordsForSyntheticEdits: max(5, 15 - falseStartMax),
            falseStartTriggerMinWords: fsTriggerMin,
            falseStartTriggerMaxWords: fsTriggerMax,
            maxFalseStartsPerMessage: falseStartMax,
            falseStartPauseMinMs: 300,
            falseStartPauseMaxMs: 700,
            maxPredictionWords: 4,
            minPredictionWords: 2,
            cursorEditTriggerMinWords: ceTriggerMin,
            cursorEditTriggerMaxWords: ceTriggerMax,
            maxCursorEditsPerMessage: cursorEditMax,
            cursorBacktrackMinChars: 4,
            cursorBacktrackMaxChars: 12,
            cursorPauseMinMs: 150,
            cursorPauseMaxMs: 420,
            cooldownWordsBetweenSyntheticEvents: cooldown,
            maxSyntheticLatencyBudgetMs: 2500 + falseStartMax * 500
        )
        updateStatusTitle()
        NSLog("HP cfg: wpm=%d pause=%d%% typo=%d%% flightCap=%dms thinkCap=%dms delay=%dms corr=%d%% burst=%dw uncertainty=%@ fs=%d ce=%d",
              wpm, pausePct, typoPct, flightCapMs, thinkCapMs, initialDelayMs, correctionSpeed, burstWords,
              uncertaintyEnabled ? "ON" : "OFF", falseStartMax, cursorEditMax)
    }

    func updateStatusTitle() {
        let u = uncertaintyEnabled ? "+" : ""
        statusItem?.button?.title = "HP \(wpm)\(u)"
    }

    func setWPM(_ v: Int) { wpm = v; applyAll(); syncToModel() }
    func setPausePct(_ v: Int) { pausePct = v; applyAll(); syncToModel() }
    func setTypoPct(_ v: Int) { typoPct = v; applyAll(); syncToModel() }
    func setFlightCap(_ v: Int) { flightCapMs = v; applyAll(); syncToModel() }
    func setThinkCap(_ v: Int) { thinkCapMs = v; applyAll(); syncToModel() }
    func setInitialDelay(_ v: Int) { initialDelayMs = v; applyAll(); syncToModel() }
    func setCorrectionSpeed(_ v: Int) { correctionSpeed = v; applyAll(); syncToModel() }
    func setBurstWords(_ v: Int) { burstWords = v; applyAll(); syncToModel() }
    func setUncertainty(_ v: Bool) { uncertaintyEnabled = v; applyAll(); syncToModel() }
    func setFalseStartMax(_ v: Int) { falseStartMax = v; applyAll(); syncToModel() }
    func setCursorEditMax(_ v: Int) { cursorEditMax = v; applyAll(); syncToModel() }
    func setApiKey(_ v: String) { openaiApiKey = v; applyAll(); syncToModel() }

    // MARK: - Menu Bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "HumanPaste") {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                button.image = img.withSymbolConfiguration(config)
                button.imagePosition = .imageLeading
            }
        }
        updateStatusTitle()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(openSettings)

        typer.onTypingStarted = { [weak self] in
            self?.statusItem.button?.title = "HP..."
        }
        typer.onTypingStopped = { [weak self] in
            self?.updateStatusTitle()
        }
    }

    func prepareSettingsWindow() {
        syncToModel()
        let hostingView = NSHostingView(rootView: SettingsView(model: settingsModel))
        let screenH = NSScreen.main?.visibleFrame.height ?? 800
        let winH = min(screenH - 40, 780)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: winH),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "HumanPaste"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.minSize = NSSize(width: 480, height: 480)
        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(white: 0.96, alpha: 1.0)
        settingsWindow = window

        // Cmd+W to close window (accessory apps have no main menu)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w" {
                self?.settingsWindow?.orderOut(nil)
                return nil
            }
            return event
        }

        // Set up minimal main menu so Cmd+Q, Cmd+W, Cmd+C etc. work
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit HumanPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func openSettings() {
        syncToModel()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Test Typing

    func testTyping() {
        let sample = """
        The quick brown fox jumps over the lazy dog. This is a comprehensive test of the HumanPaste \
        typing engine with all features enabled. The system models realistic keystroke dynamics using \
        log-logistic distributions fitted to actual human typing data from research datasets. Each \
        character gets unique flight time and dwell time based on finger distance, hand alternation, \
        and common digraph patterns that humans develop through years of practice. Cognitive pauses \
        happen naturally at sentence and clause boundaries, simulating the way people think while they \
        type. The error model introduces substitutions, omissions, insertions, and transpositions at \
        realistic rates, then corrects them with human-like backspace patterns. Fatigue accumulates \
        gradually over longer texts, causing slight slowdowns that mirror real typing sessions. Burst \
        and slow phases alternate to create the natural rhythm that distinguishes human typing from \
        automated input. When uncertainty mode is active, the engine occasionally starts typing a wrong \
        continuation, pauses as if reconsidering, backspaces the mistake, and proceeds with the correct \
        text. This false start behavior makes the output look like someone who is composing text in real \
        time rather than copying from a source. The cursor edit feature adds another layer of realism by \
        occasionally moving the cursor back to fix a perceived error, even when the text was correct. \
        Together these features create a remarkably convincing simulation of natural human typing.
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sample, forType: .string)
        let words = sample.split(separator: " ").count
        let estSec = Double(sample.count) * 12.0 / Double(wpm)
        let unc = uncertaintyEnabled ? " [uncertainty ON]" : " [uncertainty OFF]"
        settingsModel.appendLog("TEST: \(sample.count) chars, ~\(words) words. Est ~\(Int(estSec))s.\(unc) Paste in 1s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.triggerPaste()
        }
    }

    // MARK: - Hotkeys

    func setupGlobalHotkey() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let cb: CGEventTapCallBack = { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let d = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                if let tap = d.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown, let refcon else { return Unmanaged.passUnretained(event) }
            let f = event.flags
            let k = event.getIntegerValueField(.keyboardEventKeycode)
            let cs = f.contains(.maskControl) && f.contains(.maskShift)
            let d = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()

            if cs {
                switch k {
                case 9:  // V
                    DispatchQueue.main.async { d.triggerPaste() }
                    return nil
                case 30: // ]
                    DispatchQueue.main.async { d.setWPM(min(d.wpm + 10, 300)) }
                    return nil
                case 33: // [
                    DispatchQueue.main.async { d.setWPM(max(d.wpm - 10, 30)) }
                    return nil
                case 35: // P
                    DispatchQueue.main.async {
                        d.setPausePct(d.pausePct >= 80 ? 0 : d.pausePct + 20)
                    }
                    return nil
                case 17: // T
                    DispatchQueue.main.async {
                        d.setTypoPct(d.typoPct >= 80 ? 0 : d.typoPct + 25)
                    }
                    return nil
                case 32: // U
                    DispatchQueue.main.async {
                        d.setUncertainty(!d.uncertaintyEnabled)
                    }
                    return nil
                default: break
                }
            }
            if k == 53 && d.typer.typing {
                DispatchQueue.main.async { d.typer.cancel() }
            }
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: cb, userInfo: refcon) else {
            let a = NSAlert()
            a.messageText = "Accessibility required"
            a.informativeText = "System Settings > Privacy & Security > Accessibility"
            a.addButton(withTitle: "Open"); a.addButton(withTitle: "Quit")
            if a.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            NSApp.terminate(nil); return
        }
        self.eventTap = tap
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("HumanPaste: ready, %d wpm", wpm)
    }

    func triggerPaste() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        let estSec = Double(text.count) * 12.0 / Double(wpm)
        NSLog("HP: typing %d chars @ %d wpm (est %.0fs, delay %dms)", text.count, wpm, estSec, initialDelayMs)
        let delaySec = Double(initialDelayMs) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySec) { [weak self] in
            self?.typer.typeText(text)
        }
    }
}

// MARK: - .env Loader

func loadDotEnv() {
    // Search up from binary: MacOS/ → Contents/ → .app/ → HumanPaste/
    let bin = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    var dir = bin
    var candidates: [URL] = []
    for _ in 0..<5 {
        candidates.append(dir.appendingPathComponent(".env"))
        dir = dir.deletingLastPathComponent()
    }
    for url in candidates {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let val = String(parts[1]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            setenv(key, val, 0)  // 0 = don't overwrite existing
        }
        NSLog("HP: loaded .env from %@", url.path)
        return
    }
}

// MARK: - Visual Test Mode

struct EventRecord {
    let type: String        // "FALSE_START", "FORGOT_WORD", "FORGOT_CLAUSE", "REPHRASE", "MID_WORD_RESTART"
    let screenBefore: String
    let screenDuring: String  // the "mistake" state
    let screenAfter: String
    let pauseMs: Int
    let backspaceTotal: Int
}

/// Classify an event sequence into a human-readable type by analyzing the action pattern.
func classifyEvent(actions: ArraySlice<TypingAction>) -> String {
    let synthTypes = actions.compactMap { a -> String? in
        if case .syntheticType(let t) = a { return t }
        return nil
    }
    let backspaces = actions.compactMap { a -> Int? in
        if case .backspace(let n) = a { return n }
        return nil
    }
    let cursorLefts = actions.compactMap { a -> Int? in
        if case .moveCursorLeft(let n) = a { return n }
        return nil
    }
    let cursorRights = actions.compactMap { a -> Int? in
        if case .moveCursorRight(let n) = a { return n }
        return nil
    }

    // Arrow-key forgotten word/clause: cursorLeft → syntheticType → cursorRight (no backspaces)
    if cursorLefts.count >= 1 && cursorRights.count >= 1 && synthTypes.count == 1 && backspaces.isEmpty {
        let insertLen = synthTypes[0].count
        if insertLen <= 8 { return "FORGOT_WORD" }
        return "FORGOT_CLAUSE"
    }

    // False start: syntheticType → pause → backspace (one cycle, no second syntheticType after)
    if synthTypes.count == 1 && backspaces.count == 1 {
        let typed = synthTypes[0]
        // Mid-word restart: short partial word
        if typed.count <= 5 && !typed.contains(" ") {
            return "MID_WORD_RESTART"
        }
        return "FALSE_START"
    }

    // Forgotten word/clause (legacy backspace-based): backspace → syntheticType (shorter) → pause → backspace → syntheticType (longer)
    if backspaces.count >= 2 && synthTypes.count >= 2 {
        let shorter = synthTypes[0]
        let longer = synthTypes[1]
        if longer.count > shorter.count {
            let diff = longer.count - shorter.count
            if diff <= 6 { return "FORGOT_WORD" }
            return "FORGOT_CLAUSE"
        } else {
            return "REPHRASE"
        }
    }

    // Rephrase backtrack: backspace → syntheticType (alt) → pause → backspace → syntheticType (original)
    if backspaces.count == 2 && synthTypes.count == 2 {
        return "REPHRASE"
    }

    return "UNKNOWN"
}

func runVisualTest(text: String, label: String, falseStarts: Int, cursorEdits: Int, apiKey: String) {
    let hasKey = !apiKey.isEmpty || !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "").isEmpty
    let config = UncertaintyConfig(
        enabled: true,
        mode: "safe",
        predictionProvider: hasKey ? "openai" : "deterministic",
        openAIModel: "gpt-4.1-nano",
        openAITimeoutMs: 3000,
        planWindowWords: 3,
        minWordsForSyntheticEdits: max(5, 15 - falseStarts),
        falseStartTriggerMinWords: max(8, 25 - falseStarts * 2),
        falseStartTriggerMaxWords: max(15, 50 - falseStarts * 3),
        maxFalseStartsPerMessage: falseStarts,
        falseStartPauseMinMs: 300,
        falseStartPauseMaxMs: 700,
        maxPredictionWords: 4,
        minPredictionWords: 2,
        cursorEditTriggerMinWords: max(3, 10 - cursorEdits),
        cursorEditTriggerMaxWords: max(8, 30 - cursorEdits * 2),
        maxCursorEditsPerMessage: cursorEdits,
        cursorBacktrackMinChars: 4,
        cursorBacktrackMaxChars: 12,
        cursorPauseMinMs: 150,
        cursorPauseMaxMs: 420,
        cooldownWordsBetweenSyntheticEvents: max(3, 10 - falseStarts - cursorEdits),
        maxSyntheticLatencyBudgetMs: 3000 + falseStarts * 500 + cursorEdits * 400
    )

    let engine = UncertaintyEngine(
        config: config,
        predictor: PredictionProviderFactory.make(config: config, apiKeyOverride: apiKey.isEmpty ? nil : apiKey)
    )

    let wordCount = text.split(separator: " ").count

    let sem = DispatchSemaphore(value: 0)
    Task {
        let actions = await engine.buildActions(for: text)

        // Walk actions and simulate screen with cursor tracking.
        // The screen is a string buffer; cursor tracks insertion position.
        var screenChars: [Character] = []
        var cursor: Int = 0  // cursor position (index into screenChars)
        var events: [EventRecord] = []
        var i = 0

        func screenStr() -> String { String(screenChars) }

        func insertText(_ t: String) {
            let chars = Array(t)
            screenChars.insert(contentsOf: chars, at: min(cursor, screenChars.count))
            cursor += chars.count
        }

        func backspaceN(_ n: Int) {
            let deleteCount = min(n, cursor)
            let start = cursor - deleteCount
            screenChars.removeSubrange(start..<cursor)
            cursor = start
        }

        func deleteForwardN(_ n: Int) {
            let deleteCount = min(n, screenChars.count - cursor)
            screenChars.removeSubrange(cursor..<(cursor + deleteCount))
        }

        while i < actions.count {
            let action = actions[i]

            switch action {
            case .type(let t):
                insertText(t)
                i += 1

            case .syntheticType, .backspace, .pause, .deleteForward, .moveCursorLeft, .moveCursorRight:
                // Start of a synthetic event — collect all non-.type actions until next .type
                let screenBefore = screenStr()
                var eventActions: [TypingAction] = []
                var totalPause = 0
                var totalBackspace = 0
                var screenDuring = ""

                while i < actions.count {
                    if case .type = actions[i] { break }

                    let a = actions[i]
                    eventActions.append(a)

                    switch a {
                    case .syntheticType(let t):
                        insertText(t)
                        if screenDuring.isEmpty { screenDuring = screenStr() }
                    case .backspace(let n):
                        backspaceN(n)
                        totalBackspace += n
                    case .pause(let ms):
                        totalPause += ms
                    case .deleteForward(let n):
                        deleteForwardN(n)
                        totalBackspace += n
                    case .moveCursorLeft(let n):
                        cursor = max(0, cursor - n)
                    case .moveCursorRight(let n):
                        cursor = min(screenChars.count, cursor + n)
                    case .type:
                        break
                    }
                    i += 1
                }

                if screenDuring.isEmpty { screenDuring = screenStr() }

                let eventType = classifyEvent(actions: eventActions[...])
                events.append(EventRecord(
                    type: eventType,
                    screenBefore: screenBefore,
                    screenDuring: screenDuring,
                    screenAfter: screenStr(),
                    pauseMs: totalPause,
                    backspaceTotal: totalBackspace
                ))
            }
        }

        // Verify screen integrity: final screen state should match the input text
        let finalScreen = screenStr()
        let pass = finalScreen == text

        // Print results
        print("=" * 70)
        print("TEST: \(label)")
        print("=" * 70)
        print("Input: \(text.count) chars, ~\(wordCount) words")
        print("Provider: \(config.predictionProvider)")
        print("Config: fs=\(falseStarts) ce=\(cursorEdits) cooldown=\(config.cooldownWordsBetweenSyntheticEvents)")
        print("")

        if events.isEmpty {
            print("  (no events generated)")
        }

        for (idx, ev) in events.enumerated() {
            let suffix = { (s: String, n: Int) -> String in
                s.count <= n ? s : "..." + String(s.suffix(n))
            }
            print("  EVENT \(idx + 1): \(ev.type)")
            print("    before:  \"\(suffix(ev.screenBefore, 55))\"")
            print("    mistake: \"\(suffix(ev.screenDuring, 55))\"")
            print("    fixed:   \"\(suffix(ev.screenAfter, 55))\"")
            print("    pauses: \(ev.pauseMs)ms  backspaces: \(ev.backspaceTotal)")
            print("")
        }

        // Event type counts
        var counts: [String: Int] = [:]
        for ev in events { counts[ev.type, default: 0] += 1 }
        let countStr = counts.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "  ")

        print("  TOTAL: \(events.count) events  [\(countStr)]")
        print("  SCREEN INTEGRITY: \(pass ? "PASS" : "FAIL")")
        if !pass {
            print("    Expected \(text.count) chars, got \(finalScreen.count)")
            // Show first diff
            for (ci, (a, b)) in zip(finalScreen, text).enumerated() {
                if a != b {
                    print("    First diff at char \(ci): got '\(a)' expected '\(b)'")
                    break
                }
            }
            if finalScreen.count != text.count {
                let shorter = min(finalScreen.count, text.count)
                let longer = max(finalScreen.count, text.count)
                if shorter < longer {
                    let which = finalScreen.count < text.count ? "MISSING" : "EXTRA"
                    print("    \(which) \(longer - shorter) chars")
                }
            }
        }
        print("")

        sem.signal()
    }
    sem.wait()
}

// Helper: String repeat
func *(lhs: String, rhs: Int) -> String {
    String(repeating: lhs, count: rhs)
}

// MARK: - Entry Point

loadDotEnv()

// MARK: - Headless Mode (full typing simulation, no CGEvents, logs to file)

if CommandLine.arguments.contains("--headless") {
    headlessMode = true

    // Parse args
    var wpm = 80
    var pausePct = 15
    var typoPct = 50
    var fs = 2
    var ce = 2
    var logPath = "/tmp/humanpaste_headless.log"
    var inputText = ""
    var inputFile = ""

    for (idx, arg) in CommandLine.arguments.enumerated() {
        if arg == "--wpm", idx + 1 < CommandLine.arguments.count { wpm = Int(CommandLine.arguments[idx + 1]) ?? wpm }
        if arg == "--pause", idx + 1 < CommandLine.arguments.count { pausePct = Int(CommandLine.arguments[idx + 1]) ?? pausePct }
        if arg == "--typo", idx + 1 < CommandLine.arguments.count { typoPct = Int(CommandLine.arguments[idx + 1]) ?? typoPct }
        if arg == "--fs", idx + 1 < CommandLine.arguments.count { fs = Int(CommandLine.arguments[idx + 1]) ?? fs }
        if arg == "--ce", idx + 1 < CommandLine.arguments.count { ce = Int(CommandLine.arguments[idx + 1]) ?? ce }
        if arg == "--log", idx + 1 < CommandLine.arguments.count { logPath = CommandLine.arguments[idx + 1] }
        if arg == "--text", idx + 1 < CommandLine.arguments.count { inputText = CommandLine.arguments[idx + 1] }
        if arg == "--file", idx + 1 < CommandLine.arguments.count { inputFile = CommandLine.arguments[idx + 1] }
    }

    // Load input text
    if inputText.isEmpty && !inputFile.isEmpty {
        inputText = (try? String(contentsOfFile: inputFile, encoding: .utf8)) ?? ""
    }
    if inputText.isEmpty {
        inputText = "The quick brown fox jumps over the lazy dog near the riverbank. Scientists have discovered a remarkable new species of deep-sea creature that challenges our understanding of marine biology. The research team spent several months analyzing data collected from underwater sensors positioned along the continental shelf. Their findings suggest that biodiversity in the deep ocean is far greater than previously estimated by leading experts in the field. Modern technology has enabled researchers to explore previously inaccessible regions of the ocean floor, revealing complex ecosystems that thrive in extreme conditions without sunlight. These discoveries have important implications for conservation efforts and our broader understanding of life on Earth."
    }

    // Set up log file
    var logLines: [String] = []
    let logStart = CFAbsoluteTimeGetCurrent()

    func headlessLog(_ msg: String) {
        let elapsed = CFAbsoluteTimeGetCurrent() - logStart
        let line = String(format: "[%7.1fms] %@", elapsed * 1000, msg)
        logLines.append(line)
    }

    print("HUMANPASTE HEADLESS TEST")
    print("  wpm=\(wpm) pause=\(pausePct)% typo=\(typoPct)% fs=\(fs) ce=\(ce)")
    print("  input: \(inputText.count) chars, ~\(inputText.split(separator: " ").count) words")
    print("  log: \(logPath)")
    print("")

    // Configure typer
    let typer = HumanTyper()
    typer.targetWPM = wpm
    typer.speedProfile = speedProfileForWPM(wpm, pausePct: pausePct, typoPct: typoPct)
    typer.pauseConfig = pauseConfigFromPercent(pausePct)
    typer.typoMultiplier = typoMultiplierFromPercent(typoPct)
    typer.flightCapMs = 700.0
    typer.thinkCapMs = 600.0
    typer.uncertaintyEnabled = fs > 0 || ce > 0
    typer.uncertaintyConfig = UncertaintyConfig(
        enabled: fs > 0 || ce > 0,
        mode: "openai",
        predictionProvider: "openai",
        openAIModel: "gpt-4.1-nano",
        openAITimeoutMs: 900,
        planWindowWords: 3,
        minWordsForSyntheticEdits: 8,
        falseStartTriggerMinWords: 10,
        falseStartTriggerMaxWords: 80,
        maxFalseStartsPerMessage: fs,
        falseStartPauseMinMs: 220,
        falseStartPauseMaxMs: 620,
        maxPredictionWords: 6,
        minPredictionWords: 2,
        cursorEditTriggerMinWords: 12,
        cursorEditTriggerMaxWords: 60,
        maxCursorEditsPerMessage: ce,
        cursorBacktrackMinChars: 4,
        cursorBacktrackMaxChars: 12,
        cursorPauseMinMs: 150,
        cursorPauseMaxMs: 420,
        cooldownWordsBetweenSyntheticEvents: 5,
        maxSyntheticLatencyBudgetMs: 3000
    )

    // Load API key for uncertainty
    let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    if !envKey.isEmpty { typer.openaiApiKey = envKey }

    // Capture all hpLog output
    typer.logCallback = { msg in headlessLog(msg) }

    // Run typing synchronously
    headlessLog("START typing \(inputText.count) chars at \(wpm) WPM")
    typer.typeText(inputText)

    // Wait for completion
    while typer.typing {
        Thread.sleep(forTimeInterval: 0.1)
    }
    headlessLog("END")

    // Write log file
    let logContent = logLines.joined(separator: "\n")
    try? logContent.write(toFile: logPath, atomically: true, encoding: .utf8)

    // Print summary
    let totalMs = (CFAbsoluteTimeGetCurrent() - logStart) * 1000
    let effectiveWPM = Int(Double(inputText.count) / (totalMs / 1000.0) * 60.0 / 5.0)
    let typoCount = logLines.filter { $0.contains("TYPO(") }.count
    let capsFumbles = logLines.filter { $0.contains("CAPS_FUMBLE") }.count
    let postErrors = logLines.filter { $0.contains("POST_ERR") }.count
    let synthetics = logLines.filter { $0.contains("SYNTHETIC") }.count
    let thinks = logLines.filter { $0.contains("THINK") }.count
    let rollovers = logLines.filter { $0.contains("ROLLOVER") }.count

    print("RESULTS:")
    print("  Total time: \(String(format: "%.1f", totalMs / 1000))s")
    print("  Effective WPM: \(effectiveWPM) (target \(wpm))")
    print("  Typos: \(typoCount)")
    print("  Caps fumbles: \(capsFumbles)")
    print("  Post-error slowing: \(postErrors) chars affected")
    print("  Synthetic events: \(synthetics)")
    print("  Thinking pauses: \(thinks)")
    print("  Rollovers: \(rollovers)")
    print("  Log lines: \(logLines.count)")
    print("")
    print("Full log written to: \(logPath)")

    exit(0)
}

// MARK: - Visual Test Mode

if CommandLine.arguments.contains("--test") || CommandLine.arguments.contains("--dry-run") {
    var fs = 4
    var ce = 4
    var key = ""
    for (idx, arg) in CommandLine.arguments.enumerated() {
        if arg == "--fs", idx + 1 < CommandLine.arguments.count {
            fs = Int(CommandLine.arguments[idx + 1]) ?? fs
        }
        if arg == "--ce", idx + 1 < CommandLine.arguments.count {
            ce = Int(CommandLine.arguments[idx + 1]) ?? ce
        }
        if arg == "--key", idx + 1 < CommandLine.arguments.count {
            key = CommandLine.arguments[idx + 1]
        }
    }

    let tests: [(String, String)] = [
        ("Short email",
         "Hey Sarah, I wanted to follow up on our conversation from yesterday. The project deadline has been moved to Friday, so we need to finalize the design specs by Wednesday at the latest. Can you send me the updated mockups when you get a chance? Thanks!"),

        ("Technical paragraph",
         "The database migration requires careful planning. First, we need to back up all existing tables and verify the checksums. Then the schema changes can be applied incrementally, starting with the user authentication tables. After each migration step, we should run the integration tests to catch any regressions. The entire process should take about two hours, assuming no unexpected issues arise with the foreign key constraints."),

        ("Long multi-sentence",
         "The quick brown fox jumps over the lazy dog near the riverbank. Scientists have discovered a remarkable new species of deep-sea creature that challenges our understanding of marine biology. The research team spent several months analyzing data collected from underwater sensors positioned along the continental shelf. Their findings suggest that biodiversity in the deep ocean is far greater than previously estimated by leading experts in the field. Modern technology has enabled researchers to explore previously inaccessible regions of the ocean floor, revealing complex ecosystems that thrive in extreme conditions without sunlight. These discoveries have important implications for conservation efforts and our broader understanding of life on Earth."),

        ("Casual message",
         "so basically what happened was the server went down at like 3am and nobody noticed until the morning standup. the on-call engineer was asleep because the pager alert went to the wrong channel. we fixed it by restarting the primary node and then rotating the credentials, but we definitely need to update the runbook so this doesnt happen again. also we should probably set up a backup notification system just in case."),
    ]

    print("")
    print("HUMANPASTE VISUAL TEST SUITE")
    print("Each event shows what the screen looks like before, during (mistake), and after (fixed).")
    print("Review each event to verify it looks like realistic human behavior.")
    print("fs=\(fs) ce=\(ce) provider=\(key.isEmpty && (ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "").isEmpty ? "deterministic" : "openai")")
    print("")

    for (label, text) in tests {
        runVisualTest(text: text, label: label, falseStarts: fs, cursorEdits: ce, apiKey: key)
    }

    // Run test 3 again to show randomness
    print("=" * 70)
    print("REPEAT: Long multi-sentence (showing randomness)")
    print("=" * 70)
    runVisualTest(text: tests[2].1, label: "Long multi-sentence (run 2)", falseStarts: fs, cursorEdits: ce, apiKey: key)

    exit(0)
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.run()
}
