import SwiftUI
import Cocoa

// MARK: - Settings Model

class SettingsModel: ObservableObject {
    @Published var wpm: Double = 80
    @Published var pausePct: Double = 15
    @Published var typoPct: Double = 50
    @Published var flightCapMs: Double = 700
    @Published var thinkCapMs: Double = 600
    @Published var initialDelayMs: Double = 200
    @Published var correctionSpeed: Double = 100
    @Published var burstWords: Double = 5
    @Published var uncertaintyEnabled: Bool = true
    @Published var falseStartMax: Double = 2
    @Published var cursorEditMax: Double = 1
    @Published var openaiApiKey: String = ""
    @Published var logText: String = ""
    @Published var activePreset: Int = -1
    @Published var verboseLog: Bool = false

    var applyCallback: (() -> Void)?
    var testCallback: (() -> Void)?

    static let logFileURL: URL = {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("HumanPaste.log")
    }()

    func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)\n"
        logText += line

        if let data = line.data(using: .utf8),
           let fh = try? FileHandle(forWritingTo: Self.logFileURL) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            try? line.write(to: Self.logFileURL, atomically: false, encoding: .utf8)
        }
    }

    private let presetConfigs: [(wpm: Double, pause: Double, typo: Double, delay: Double,
                                  corr: Double, burst: Double, unc: Bool, fs: Double, ce: Double)] = [
        (75, 20, 45, 150, 90, 4, true, 2, 1),
        (160, 5, 15, 0, 150, 8, false, 0, 0),
        (90, 12, 35, 2500, 100, 5, true, 2, 1),
        (50, 35, 60, 400, 70, 3, true, 3, 2),
        (60, 30, 70, 300, 80, 3, true, 20, 10),
    ]

    func applyPreset(_ index: Int) {
        guard index < presetConfigs.count else { return }
        let p = presetConfigs[index]
        wpm = p.wpm; pausePct = p.pause; typoPct = p.typo
        initialDelayMs = p.delay; correctionSpeed = p.corr
        burstWords = p.burst; uncertaintyEnabled = p.unc
        falseStartMax = p.fs; cursorEditMax = p.ce
        activePreset = index
        applyCallback?()
        appendLog("Preset: wpm=\(Int(p.wpm)) pause=\(Int(p.pause))% typo=\(Int(p.typo))% fs=\(Int(p.fs)) ce=\(Int(p.ce))")
    }

    func apply() { applyCallback?() }
}

// MARK: - Theme

private enum HP {
    static let bg        = Color(white: 0.96)
    static let card      = Color.white
    static let accent    = Color(red: 0.22, green: 0.42, blue: 0.88)
    static let dim       = Color(white: 0.50)
    static let label     = Color(white: 0.22)
    static let sublabel  = Color(white: 0.45)
    static let border    = Color(white: 0.88)
    static let logGreen  = Color(red: 0.30, green: 0.78, blue: 0.45)
    static let logBg     = Color(white: 0.10)
    static let logDim    = Color(white: 0.38)
    static let danger    = Color(red: 0.82, green: 0.22, blue: 0.22)
}

// MARK: - Tooltip Descriptions

private let tooltips: [String: String] = [
    "wpm": "Target words per minute. The engine varies around this with burst/slow phases.",
    "pauses": "Cognitive pause frequency. Higher = more thinking pauses at sentence boundaries.",
    "typos": "Error rate multiplier. Controls substitution, omission, insertion, transposition typos.",
    "flight cap": "Max inter-key interval (ms). Caps the log-logistic distribution tail.",
    "think cap": "Max thinking pause duration (ms). Caps cognitive pauses at clause/sentence boundaries.",
    "start delay": "Delay before first keystroke (ms). Simulates reading/composing before typing.",
    "correction": "Error correction speed. 100%=normal, 200%=fast backspace, 50%=slow hesitant fix.",
    "burst len": "Words per fast-typing burst. After a burst, speed drops briefly (burst/slow cycling).",
    "false starts": "Max false-start events. Types a wrong continuation (AI-predicted), pauses, deletes, retypes correct.",
    "cursor edits": "Max cursor-edit events. Forgotten words, forgotten clauses, mid-word restarts, rephrase backtracks.",
]

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    presets
                    typingCard
                    timingCard
                    uncertaintyCard
                    hotkeys
                    buttons
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            logPanel
        }
        .frame(minWidth: 460, minHeight: 520)
        .background(HP.bg)
        .preferredColorScheme(.light)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("HumanPaste")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(HP.label)
            Text("v3")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(HP.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(HP.accent.opacity(0.10))
                .cornerRadius(3)
            Spacer()
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(HP.dim.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Quit HumanPaste")
        }
    }

    // MARK: Presets

    private var presets: some View {
        HStack(spacing: 5) {
            presetBtn(0, "Natural", "75wpm, balanced errors and pauses")
            presetBtn(1, "Fast", "160wpm, minimal errors, no uncertainty")
            presetBtn(2, "AI Paste", "90wpm, 2.5s start delay, composing feel")
            presetBtn(3, "Careful", "50wpm, high errors, deliberate typing")
            presetBtn(4, "Test", "Everything cranked up for dev testing")
        }
    }

    private func presetBtn(_ idx: Int, _ name: String, _ tip: String) -> some View {
        let active = model.activePreset == idx
        return Button(action: { model.applyPreset(idx) }) {
            Text(name)
                .font(.system(size: 10, weight: active ? .semibold : .medium))
                .foregroundColor(active ? .white : HP.sublabel)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active ? HP.accent : HP.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(active ? Color.clear : HP.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    // MARK: Typing Card

    private var typingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 1) {
                cardLabel("Speed & Errors")
                row("wpm", $model.wpm, 30...300, "wpm")
                row("pauses", $model.pausePct, 0...100, "%")
                row("typos", $model.typoPct, 0...100, "%")
                row("correction", $model.correctionSpeed, 25...200, "%")
                row("burst len", $model.burstWords, 1...15, "w")
            }
        }
    }

    // MARK: Timing Card

    private var timingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 1) {
                cardLabel("Timing")
                row("flight cap", $model.flightCapMs, 50...800, "ms")
                row("think cap", $model.thinkCapMs, 100...3000, "ms")
                row("start delay", $model.initialDelayMs, 0...5000, "ms")
            }
        }
    }

    // MARK: Uncertainty Card

    private var uncertaintyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    cardLabel("Uncertainty Engine")
                    Spacer()
                    Toggle("", isOn: $model.uncertaintyEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .onChange(of: model.uncertaintyEnabled) { model.apply() }
                        .help("Enable false starts, forgotten words, rephrasing, mid-word restarts")
                }

                if model.uncertaintyEnabled {
                    row("false starts", $model.falseStartMax, 0...20, "")
                    row("cursor edits", $model.cursorEditMax, 0...10, "")

                    HStack(spacing: 6) {
                        Text("api key")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(HP.sublabel)
                            .frame(width: 72, alignment: .trailing)
                        SecureField("sk-... (optional, uses deterministic fallback)", text: $model.openaiApiKey)
                            .font(.system(size: 10, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: model.openaiApiKey) { model.apply() }
                    }
                    .padding(.top, 4)
                    .help("OpenAI API key for AI-generated false start phrases. Without it, deterministic phrases are used.")
                } else {
                    Text("False starts, forgotten words, mid-word restarts, and rephrasing are off")
                        .font(.system(size: 9.5))
                        .foregroundColor(HP.dim)
                        .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: Hotkeys

    private var hotkeys: some View {
        HStack(spacing: 10) {
            keycap("^⇧V", "Paste")
            keycap("^⇧]", "WPM+")
            keycap("^⇧[", "WPM\u{2212}")
            keycap("^⇧P", "Pause")
            keycap("^⇧T", "Typo")
            keycap("^⇧U", "Uncert")
            keycap("Esc", "Stop")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func keycap(_ key: String, _ action: String) -> some View {
        VStack(spacing: 2) {
            Text(key)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundColor(HP.label)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.08), radius: 0.5, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5)
                        .stroke(HP.border, lineWidth: 0.5)
                )
            Text(action)
                .font(.system(size: 7.5, weight: .medium))
                .foregroundColor(HP.dim)
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: 8) {
            Button(action: { model.testCallback?() }) {
                Label("Test", systemImage: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(HP.accent)
                    )
            }
            .buttonStyle(.plain)
            .help("Copies a sample paragraph to clipboard and types it with current settings")

            Button(action: { model.logText = "" }) {
                Text("Clear Log")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(HP.sublabel)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(HP.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(HP.border, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: Log Panel

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.logText.isEmpty ? HP.logDim : HP.logGreen)
                    .frame(width: 5, height: 5)
                Text("LOG")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(HP.logDim)
                    .kerning(0.5)
                Spacer()
                Button(action: { model.verboseLog.toggle() }) {
                    Text(model.verboseLog ? "verbose" : "compact")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(model.verboseLog ? HP.logGreen : HP.logDim)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(white: model.verboseLog ? 0.18 : 0.14))
                        )
                }
                .buttonStyle(.plain)
                .help("Compact: events only. Verbose: per-character timing data.")
                if !model.logText.isEmpty {
                    Text("\(model.logText.components(separatedBy: "\n").count - 1)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(HP.logDim)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 5)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.logText.isEmpty ? "Waiting for activity..." : model.logText)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(model.logText.isEmpty
                            ? Color(white: 0.30)
                            : HP.logGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .id("bottom")
                }
                .background(HP.logBg)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(white: 0.06), lineWidth: 0.5)
                )
                .padding(.horizontal, 20)
                .onChange(of: model.logText) {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .frame(height: 110)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(white: 0.93))
    }

    // MARK: Components

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(HP.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(HP.border, lineWidth: 0.5)
            )
    }

    private func cardLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(HP.dim)
            .kerning(0.8)
            .padding(.bottom, 3)
    }

    private func row(_ label: String, _ value: Binding<Double>,
                     _ range: ClosedRange<Double>, _ unit: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(HP.sublabel)
                .frame(width: 72, alignment: .trailing)
                .padding(.trailing, 8)

            Slider(value: value, in: range, step: 1)
                .controlSize(.small)
                .accentColor(HP.accent)
                .onChange(of: value.wrappedValue) { model.apply() }

            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(HP.label)
                .frame(width: 32, alignment: .trailing)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(HP.dim)
                    .fixedSize()
                    .frame(width: 20, alignment: .leading)
                    .padding(.leading, 2)
            } else {
                Spacer().frame(width: 22)
            }
        }
        .frame(height: 22)
        .help(tooltips[label] ?? "")
    }
}
