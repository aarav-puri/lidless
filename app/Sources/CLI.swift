// The `lidless` command line tool. Same binary as the app, picked by its arguments.
import AppKit
import Foundation

enum CLI {
    static let usage = """
    usage:
      lidless run -- <command> [args...]   keep the Mac awake until the command exits
      lidless status                       show what Lidless is holding for
      lidless hook start|stop              used by the Claude Code hooks

    """

    /// Returns an exit code, or nil when the arguments mean "launch the app".
    static func main(_ args: [String]) -> Int32? {
        guard let command = args.first else { return nil }
        switch command {
        case "run": return runCommand(Array(args.dropFirst()))
        case "status": return status()
        case "hook": return hook(args.dropFirst().first ?? "")
        case "--self-test": return SelfTest.run()
        case "--render-icons":
            for (name, st) in [("off", StatusIcon.State.off), ("waiting", .waiting), ("working", .working), ("paused", .paused)] {
                let img = StatusIcon.image(st)
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 144, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 160, height: 144).fill()
                img.draw(in: NSRect(x: 0, y: 0, width: 160, height: 144)); NSGraphicsContext.restoreGraphicsState()
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: (args.count > 1 ? args[1] : ".") + "/status-\(name).png"))
            }
            return 0
        case "help", "--help", "-h": print(usage, terminator: ""); return 0
        default:
            if command.hasPrefix("-psn") || command.hasPrefix("-NS") || command.hasPrefix("-Apple") { return nil }
            FileHandle.standardError.write(Data(usage.utf8)); return 64
        }
    }

    // MARK: hook

    /// Claude Code hook. UserPromptSubmit starts a hold for the session, Stop and SessionEnd end it.
    static func hook(_ action: String) -> Int32 {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        let session = (json["session_id"] as? String) ?? "pid-\(agentAncestor())"
        let id = "claude-" + session
        switch action {
        case "start":
            let old = HoldStore.live().first { $0.id == id }
            HoldStore.write(Hold(id: id, pid: agentAncestor(), label: "Claude Code", kind: "hook",
                                 started: old?.started ?? Date().timeIntervalSince1970))
            launchAppIfNeeded()
        case "stop":
            HoldStore.remove(id: id)
        default: break
        }
        return 0
    }

    // MARK: run

    static func runCommand(_ raw: [String]) -> Int32 {
        var args = raw
        if args.first == "--" { args.removeFirst() }
        guard !args.isEmpty else { FileHandle.standardError.write(Data(usage.utf8)); return 64 }

        let id = "run-\(getpid())"
        HoldStore.write(Hold(id: id, pid: getpid(), label: (args[0] as NSString).lastPathComponent, kind: "run",
                             started: Date().timeIntervalSince1970))
        launchAppIfNeeded()
        defer { HoldStore.remove(id: id) }

        // Ctrl-C goes to the child (same process group). The parent waits so it can always clean up.
        signal(SIGINT, SIG_IGN); signal(SIGQUIT, SIG_IGN)
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        var defaults = sigset_t()
        sigemptyset(&defaults); sigaddset(&defaults, SIGINT); sigaddset(&defaults, SIGQUIT); sigaddset(&defaults, SIGTERM)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSIGDEF))
        defer { posix_spawnattr_destroy(&attr) }

        let argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var child: pid_t = 0
        let rc = posix_spawnp(&child, args[0], nil, &attr, argv, environ)
        guard rc == 0 else {
            FileHandle.standardError.write(Data("lidless: \(args[0]): \(String(cString: strerror(rc)))\n".utf8))
            return 127
        }
        var status: Int32 = 0
        while waitpid(child, &status, 0) == -1 && errno == EINTR {}
        let sig = status & 0x7f
        return sig == 0 ? (status >> 8) & 0xff : 128 + sig
    }

    // MARK: status

    static func status() -> Int32 {
        let holds = HoldStore.live()
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        print("Lidless app: \(running ? "running" : "not running")")
        print("Lid sleep: \(Power.lidSleepDisabled ? "disabled (awake)" : "normal")")
        if holds.isEmpty { print("Holds: none") }
        for h in holds { print("  \(h.label)  pid \(h.pid)  since \(DateFormatter.localizedString(from: h.startedDate, dateStyle: .none, timeStyle: .short))") }
        return 0
    }

    static let bundleID = "app.personal.lidless"

    static func launchAppIfNeeded() {
        guard ProcessInfo.processInfo.environment["LIDLESS_HOME"] == nil,
              NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return }
        run("/usr/bin/open", ["-g", "-b", bundleID])
    }
}

// MARK: - Self-test

enum SelfTest {
    static var failures = 0

    static func check(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; print("FAIL: \(what)") }
    }

    static func run() -> Int32 {
        // Agent matching.
        check(Agents.match("/Users/a/.local/bin/claude --dangerously-skip-permissions") == "claude", "native claude")
        check(Agents.match("node /opt/homebrew/bin/claude") == "claude", "node claude")
        check(Agents.match("/opt/homebrew/bin/node /opt/homebrew/lib/node_modules/@google/gemini-cli/dist/gemini.js") == "gemini", "gemini js")
        check(Agents.match("codex exec fix the tests") == "codex", "codex")
        check(Agents.match("python3 -m pip install aider") == nil, "python flags skipped")
        check(Agents.match("/Applications/Claude.app/Contents/MacOS/Claude") == nil, "Claude desktop is not an agent")
        check(Agents.match("/usr/bin/vim notes.txt") == nil, "vim")
        check(Agents.match("/Users/a/.local/bin/claude --chrome-native-host") == nil, "chrome bridge ignored")

        // ps parsing and tree CPU.
        let ps = """
          100     1   0.5 /Users/a/.local/bin/claude
          101   100  12.0 /bin/zsh -c npm test
          102   101   30,5 node jest
          200     1   0.0 codex
          201   200   0.0 codex --child
          300     1   0.0 /usr/bin/vim
        """
        let procs = Agents.parsePS(ps)
        check(procs.count == 6, "parse ps (\(procs.count))")
        let agents = findAgents(in: procs)
        check(agents.count == 2, "wrapper deduped (\(agents.count))")
        if let c = agents.first(where: { $0.key == "claude" }) { check(abs(c.treeCPU - 43.0) < 0.01, "tree cpu \(c.treeCPU)") }
        else { check(false, "claude found") }

        // Hold files, in a scratch directory.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lidless-selftest-\(getpid())")
        Paths.support = tmp
        defer { try? FileManager.default.removeItem(at: tmp) }
        HoldStore.write(Hold(id: "claude-abc/../x", pid: getpid(), label: "Claude Code", kind: "hook", started: 1))
        HoldStore.write(Hold(id: "dead", pid: 999_999, label: "gone", kind: "run", started: 2))
        let live = HoldStore.live()
        check(live.count == 1 && live.first?.label == "Claude Code", "live holds (\(live.count))")
        check(!FileManager.default.fileExists(atPath: HoldStore.url(for: "dead").path), "dead hold removed")
        check(HoldStore.url(for: "claude-abc/../x").lastPathComponent == "claude-abc____x.json", "hold ids are sanitised")
        HoldStore.remove(id: "claude-abc/../x")
        check(HoldStore.live().isEmpty, "hold removed")

        // Sudoers rule passes visudo and allows nothing beyond the two pmset commands.
        let line = Power.sudoersLine(user: "someone")
        check(line == "someone ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0\n", "sudoers line")
        let rule = tmp.appendingPathComponent("rule")
        try? line.write(to: rule, atomically: true, encoding: .utf8)
        check(Lidless_run("/usr/sbin/visudo", ["-cf", rule.path]).status == 0, "visudo accepts rule")

        // Claude settings merge keeps other hooks and is idempotent.
        let settings: [String: Any] = ["model": "opus", "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
        let merged = ClaudeHooks.merged(settings, binary: "/Applications/Lidless.app/Contents/MacOS/Lidless", install: true)
        let twice = ClaudeHooks.merged(merged, binary: "/Applications/Lidless.app/Contents/MacOS/Lidless", install: true)
        check(ClaudeHooks.isInstalled(in: merged), "hooks installed")
        check(StatusIcon.image(.working).isTemplate, "status icon")
        check(((twice["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 2, "stop hooks idempotent")
        check(((twice["hooks"] as? [String: Any])?["UserPromptSubmit"] as? [Any])?.count == 1, "prompt hook once")
        let removed = ClaudeHooks.merged(twice, binary: "x", install: false)
        check(!ClaudeHooks.isInstalled(in: removed), "hooks removed")
        check(((removed["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 1, "other hooks kept")
        check(removed["model"] as? String == "opus", "other settings kept")

        print(failures == 0 ? "self-test passed" : "self-test failed: \(failures)")
        return failures == 0 ? 0 : 1
    }
}

// Disambiguates the free function from `SelfTest.run`.
@discardableResult
func Lidless_run(_ path: String, _ args: [String]) -> (status: Int32, output: String) { run(path, args) }
