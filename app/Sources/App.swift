// The menubar app: watches agents, holds the Mac awake while one is working, lets go when they finish.
import AppKit
import ServiceManagement

struct Source {
    var label: String
    var since: Date
}

final class Monitor {
    static let busyCPU = 1.0              // percent, agent plus children
    static let quietWindow: TimeInterval = 120
    static let staleHook: TimeInterval = 15 * 60

    private var lastBusy: [Int32: Date] = [:]
    private var workStart: [Int32: Date] = [:]
    private var firstSeen: [Int32: Date] = [:]

    func sources(hooksInstalled: Bool, now: Date = Date()) -> [Source] {
        let agents = findAgents(in: Agents.snapshot())
        let alive = Set(agents.map(\.pid))
        for pid in Array(lastBusy.keys) where !alive.contains(pid) { lastBusy[pid] = nil; workStart[pid] = nil }
        for pid in Array(firstSeen.keys) where !alive.contains(pid) { firstSeen[pid] = nil }

        var out: [Source] = []
        for a in agents {
            if firstSeen[a.pid] == nil { firstSeen[a.pid] = now }
            if a.treeCPU >= Monitor.busyCPU {
                lastBusy[a.pid] = now
                if workStart[a.pid] == nil { workStart[a.pid] = now }
            } else if let last = lastBusy[a.pid], now.timeIntervalSince(last) > Monitor.quietWindow {
                workStart[a.pid] = nil
            }
            // With hooks, Claude Code reports its own start and finish exactly.
            if a.key == "claude" && hooksInstalled { continue }
            if let start = workStart[a.pid] { out.append(Source(label: Agents.known[a.key] ?? a.key, since: start)) }
        }

        for hold in HoldStore.live() {
            if hold.kind == "hook", let seen = firstSeen[hold.pid], now.timeIntervalSince(seen) > Monitor.staleHook,
               now.timeIntervalSince(lastBusy[hold.pid] ?? seen) > Monitor.staleHook {
                // The session went quiet without a Stop event (an interrupted turn). Let it go.
                HoldStore.remove(id: hold.id); continue
            }
            out.append(Source(label: hold.label, since: hold.startedDate))
        }
        return out.sorted { $0.since < $1.since }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitor = Monitor()
    private let idle = IdleAssertion()
    private var timer: Timer?
    private var sources: [Source] = []
    private var holding = false
    private var pausedReason: String?
    private var hooksInstalled = false

    private let defaults = UserDefaults.standard
    private var armed: Bool {
        get { defaults.object(forKey: "armed") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "armed"); tick() }
    }
    private var engagedMarker: URL { Paths.support.appendingPathComponent("engaged") }

    func applicationDidFinishLaunching(_ note: Notification) {
        HoldStore.ensureDir()
        // A previous run that ended without cleaning up (crash, force quit) leaves lid sleep off. Restore it.
        if FileManager.default.fileExists(atPath: engagedMarker.path) {
            Power.setLidSleepDisabled(false)
            try? FileManager.default.removeItem(at: engagedMarker)
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 1

        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }

        if !defaults.bool(forKey: "setupShown") {
            defaults.set(true, forKey: "setupShown")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showSetup() }
        }
    }
    private var signalSources: [DispatchSourceSignal] = []

    func applicationWillTerminate(_ note: Notification) {
        if holding { release(sleepIfClosed: false) }
    }

    // MARK: Loop

    private func tick() {
        syncHooks()
        sources = armed ? monitor.sources(hooksInstalled: hooksInstalled) : []

        pausedReason = nil
        if ProcessInfo.processInfo.thermalState == .critical { pausedReason = "Paused: Mac is too hot" }
        if let b = Power.battery(), b.onBattery, b.percent <= 20 { pausedReason = "Paused: battery at \(b.percent)%" }

        let want = armed && Power.isAuthorized && !sources.isEmpty && pausedReason == nil
        if want && !holding { engage() }
        if !want && holding { release(sleepIfClosed: true) }
        updateIcon()
    }

    private func engage() {
        guard Power.setLidSleepDisabled(true) else { return }
        FileManager.default.createFile(atPath: engagedMarker.path, contents: nil)
        idle.take(reason: "Lidless: an agent is working")
        holding = true
    }

    private func release(sleepIfClosed: Bool) {
        Power.setLidSleepDisabled(false)
        try? FileManager.default.removeItem(at: engagedMarker)
        idle.release()
        holding = false
        // The agent finished with the lid shut and no external display: go to sleep now instead of waiting.
        if sleepIfClosed && Power.lidClosed && NSScreen.screens.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if !self.holding && Power.lidClosed { Power.sleepNow() }
            }
        }
    }

    private func updateIcon() {
        let state: StatusIcon.State
        if !armed { state = .off }
        else if pausedReason != nil { state = .paused }
        else if holding { state = .working }
        else { state = .waiting }
        item.button?.image = StatusIcon.image(state)
        item.button?.toolTip = statusLine
    }

    private var statusLine: String {
        if !armed { return "Cloud Mode is off" }
        if !Power.isAuthorized { return "Needs permission to keep the lid awake" }
        if let p = pausedReason { return p }
        if holding { return sources.count == 1 ? "Awake until the agent finishes" : "Awake until \(sources.count) agents finish" }
        return "Waiting for an agent"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        tick()
        menu.removeAllItems()

        let toggle = NSMenuItem(title: "Cloud Mode", action: #selector(toggleArmed), keyEquivalent: "")
        toggle.state = armed ? .on : .off
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        for s in sources {
            let row = NSMenuItem(title: "\(s.label)  ·  \(Self.elapsed(since: s.since))", action: nil, keyEquivalent: "")
            row.isEnabled = false
            row.indentationLevel = 1
            row.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 7, weight: .regular).applying(.init(paletteColors: [.systemGreen])))
            menu.addItem(row)
        }
        if armed && !Power.isAuthorized {
            let allow = NSMenuItem(title: "Allow Lid-Closed Awake…", action: #selector(authorize), keyEquivalent: "")
            allow.target = self
            menu.addItem(allow)
        }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        menu.addItem(login)

        if !FileManager.default.fileExists(atPath: Paths.cliLink) {
            let cli = NSMenuItem(title: "Install Command Line Tool…", action: #selector(authorize), keyEquivalent: "")
            cli.target = self
            menu.addItem(cli)
        }
        menu.addItem(.separator())
        let uninstall = NSMenuItem(title: "Uninstall…", action: #selector(uninstall), keyEquivalent: "")
        uninstall.target = self
        menu.addItem(uninstall)
        menu.addItem(NSMenuItem(title: "Quit Lidless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    static func elapsed(since date: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(date)))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }

    // MARK: Actions

    @objc private func toggleArmed() {
        armed.toggle()
        if armed && !Power.isAuthorized { authorize() }
    }

    /// Keeps the Claude Code hooks installed in the background, pointing at this copy of the app.
    /// Runs every tick but only writes when they are missing or stale. Never touches a file it can't parse.
    private var hookWriteFailed = false
    private func syncHooks() {
        let binary = Bundle.main.executablePath ?? ""
        let claudeDir = ClaudeHooks.settingsURL.deletingLastPathComponent().path
        guard !binary.isEmpty, FileManager.default.fileExists(atPath: claudeDir) else { hooksInstalled = false; return }
        if !ClaudeHooks.isCurrent(binary: binary) && !hookWriteFailed {
            do { try ClaudeHooks.set(installed: true, binary: binary) } catch { hookWriteFailed = true }
        }
        hooksInstalled = ClaudeHooks.isInstalled
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { alert("Couldn't change Open at Login", error.localizedDescription) }
    }

    /// Installs the sudoers rule for the two pmset commands and the `lidless` link, behind one admin prompt.
    @objc private func authorize() {
        let user = NSUserName()
        guard !user.isEmpty, user.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }),
              let binary = Bundle.main.executablePath, !binary.contains("'") else { return }
        let script = """
        set -e
        tmp=$(/usr/bin/mktemp)
        printf '%s' '\(Power.sudoersLine(user: user))' > "$tmp"
        /usr/sbin/visudo -cf "$tmp" >/dev/null
        /usr/bin/install -m 0440 -o root -g wheel "$tmp" \(Paths.sudoers)
        /bin/rm -f "$tmp"
        /bin/mkdir -p /usr/local/bin
        /bin/ln -sf '\(binary)' \(Paths.cliLink)
        """
        runAsAdmin(script, prompt: "Lidless needs permission to keep your Mac awake with the lid closed.")
        tick()
    }

    @objc private func uninstall() {
        let a = NSAlert()
        a.messageText = "Uninstall Lidless?"
        a.informativeText = "Removes the pmset permission, the lidless command, and the Claude Code hooks, restores normal sleep, then moves the app to the Trash."
        a.addButton(withTitle: "Uninstall")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        if holding { release(sleepIfClosed: false) }
        try? ClaudeHooks.set(installed: false, binary: "")
        try? SMAppService.mainApp.unregister()
        let ok = runAsAdmin("""
        /bin/rm -f \(Paths.sudoers)
        if [ -L \(Paths.cliLink) ]; then /bin/rm -f \(Paths.cliLink); fi
        \(Paths.pmset) -a disablesleep 0
        """, prompt: "Lidless needs permission to remove its pmset rule.")
        guard ok else { return }
        try? FileManager.default.removeItem(at: Paths.support)
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in NSApp.terminate(nil) }
    }

    @discardableResult
    private func runAsAdmin(_ script: String, prompt: String) -> Bool {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lidless-\(UUID().uuidString).sh")
        guard (try? script.write(to: file, atomically: true, encoding: .utf8)) != nil else { return false }
        defer { try? FileManager.default.removeItem(at: file) }
        let source = "do shell script \"/bin/sh \" & quoted form of \"\(file.path)\" with prompt \"\(prompt)\" with administrator privileges"
        var error: NSDictionary?
        NSApp.activate(ignoringOtherApps: true)
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) != -128 {
            alert("Setup didn't finish", (error[NSAppleScript.errorMessage] as? String) ?? "Unknown error")
        }
        return error == nil
    }

    private func showSetup() {
        let a = NSAlert()
        a.messageText = "Cloud Mode for your agents"
        a.informativeText = """
        Lidless keeps your Mac awake with the lid closed while an agent is working, and lets it sleep the moment the work is done.

        Set Up asks for your password once to allow two commands: pmset disablesleep 1 and 0. Claude Code turns are tracked automatically.
        """
        a.addButton(withTitle: "Set Up")
        a.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        authorize()
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
