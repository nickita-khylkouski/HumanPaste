import Cocoa
import Foundation

final class CaptureTextView: NSTextView {
    weak var recorder: MotorDNARecorder?

    override func keyDown(with event: NSEvent) {
        let key = keyLabel(event)
        let ch = typedCharacter(event)
        let cursor = selectedRange().location

        switch event.keyCode {
        case 51:
            recorder?.recordBackspace(app: NSWorkspace.shared.frontmostApplication?.localizedName, cursorIndex: cursor)
        case 117:
            recorder?.recordDeleteForward(app: NSWorkspace.shared.frontmostApplication?.localizedName, cursorIndex: cursor)
        case 123:
            recorder?.recordCursorLeft(app: NSWorkspace.shared.frontmostApplication?.localizedName, cursorIndex: cursor)
        case 124:
            recorder?.recordCursorRight(app: NSWorkspace.shared.frontmostApplication?.localizedName, cursorIndex: cursor)
        default:
            recorder?.recordKeyDown(
                key: key,
                keyCode: Int(event.keyCode),
                character: ch,
                app: NSWorkspace.shared.frontmostApplication?.localizedName,
                cursorIndex: cursor
            )
        }

        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        let key = keyLabel(event)
        let ch = typedCharacter(event)
        let cursor = selectedRange().location

        if ![51, 117, 123, 124].contains(event.keyCode) {
            recorder?.recordKeyUp(
                key: key,
                keyCode: Int(event.keyCode),
                character: ch,
                app: NSWorkspace.shared.frontmostApplication?.localizedName,
                cursorIndex: cursor
            )
        }

        super.keyUp(with: event)
    }

    private func typedCharacter(_ event: NSEvent) -> Character? {
        guard let chars = event.characters, let c = chars.first else { return nil }
        if let scalar = c.unicodeScalars.first, scalar.value < 32 {
            return nil
        }
        return c
    }

    private func keyLabel(_ event: NSEvent) -> String {
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return String(chars.prefix(1))
        }
        switch event.keyCode {
        case 49: return "space"
        case 36: return "return"
        case 48: return "tab"
        case 51: return "backspace"
        case 117: return "deleteForward"
        case 123: return "leftArrow"
        case 124: return "rightArrow"
        default: return "k\(event.keyCode)"
        }
    }
}

final class RecorderController: NSWindowController {
    private let recorder: MotorDNARecorder
    private let outputURL: URL
    private let statusLabel = NSTextField(labelWithString: "Recording started. Type in the box below. Cmd+S to save.")

    init(recorder: MotorDNARecorder, outputURL: URL) {
        self.recorder = recorder
        self.outputURL = outputURL

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "HumanPaste Calibration Recorder (Consent Session)"
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let info = NSTextField(wrappingLabelWithString:
            "Consent-based capture only. This window records keystroke timing while it is focused.\\n"
            + "Suggested: type naturally for 3-5 minutes with punctuation, corrections, and mixed casing."
        )
        info.frame = NSRect(x: 20, y: 500, width: 820, height: 40)
        info.font = .systemFont(ofSize: 12)
        content.addSubview(info)

        statusLabel.frame = NSRect(x: 20, y: 472, width: 820, height: 18)
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .systemBlue
        content.addSubview(statusLabel)

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 70, width: 820, height: 390))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let textView = CaptureTextView(frame: NSRect(x: 0, y: 0, width: 820, height: 390))
        textView.minSize = NSSize(width: 0, height: 390)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.string = "Start typing here..."
        textView.recorder = recorder

        scroll.documentView = textView
        content.addSubview(scroll)

        let saveBtn = NSButton(title: "Save Session", target: self, action: #selector(saveSession))
        saveBtn.frame = NSRect(x: 20, y: 20, width: 120, height: 32)
        saveBtn.bezelStyle = .rounded
        content.addSubview(saveBtn)

        let quitBtn = NSButton(title: "Save & Quit", target: self, action: #selector(saveAndQuit))
        quitBtn.frame = NSRect(x: 150, y: 20, width: 120, height: 32)
        quitBtn.bezelStyle = .rounded
        content.addSubview(quitBtn)

        let hint = NSTextField(labelWithString: "Cmd+S = Save   Cmd+Q = Quit")
        hint.frame = NSRect(x: 680, y: 27, width: 160, height: 18)
        hint.textColor = .secondaryLabelColor
        content.addSubview(hint)

        window?.initialFirstResponder = textView
    }

    @objc func saveSession() {
        do {
            try recorder.saveJSON(to: outputURL)
            statusLabel.stringValue = "Saved: \(outputURL.path)"
            statusLabel.textColor = .systemGreen
        } catch {
            statusLabel.stringValue = "Save failed: \(error.localizedDescription)"
            statusLabel.textColor = .systemRed
        }
    }

    @objc func saveAndQuit() {
        saveSession()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }
}

struct Args {
    var userId = "local-user"
    var consent = "consent-local"
    var out = FileManager.default.currentDirectoryPath + "/HumanPaste/research/motordna_session_live.json"
    var captureContent = false
    var appContext = "CalibrationWindow"
}

func parseArgs() -> Args {
    var a = Args()
    var i = 1
    while i < CommandLine.arguments.count {
        let token = CommandLine.arguments[i]
        if token == "--user", i + 1 < CommandLine.arguments.count {
            a.userId = CommandLine.arguments[i + 1]
            i += 2
            continue
        }
        if token == "--consent", i + 1 < CommandLine.arguments.count {
            a.consent = CommandLine.arguments[i + 1]
            i += 2
            continue
        }
        if token == "--out", i + 1 < CommandLine.arguments.count {
            a.out = CommandLine.arguments[i + 1]
            i += 2
            continue
        }
        if token == "--no-content" {
            a.captureContent = false
            i += 1
            continue
        }
        i += 1
    }
    return a
}

@main
struct CalibrationRecorderMain {
    static func main() {
        let args = parseArgs()
        let recorder = MotorDNARecorder(
            userId: args.userId,
            consentToken: args.consent,
            captureContent: args.captureContent,
            appContext: args.appContext,
            promptId: "live-calibration",
            promptText: "Natural typing sample"
        )

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let outputURL = URL(fileURLWithPath: args.out)
        let controller = RecorderController(recorder: recorder, outputURL: outputURL)
        controller.showWindow(nil)
        app.activate(ignoringOtherApps: true)

        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Save Session", action: #selector(RecorderController.saveSession), keyEquivalent: "s").target = controller
        appMenu.addItem(withTitle: "Save & Quit", action: #selector(RecorderController.saveAndQuit), keyEquivalent: "q").target = controller
        appItem.submenu = appMenu
        app.mainMenu = menu

        app.run()
    }
}
