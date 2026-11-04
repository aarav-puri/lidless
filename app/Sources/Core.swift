// Shared pieces used by both the menubar app and the command line tool:
// hold files, process scanning, agent matching and power control.
import Foundation
import IOKit.ps
import IOKit.pwr_mgt

enum Paths {
    static var support: URL = {
        if let override = ProcessInfo.processInfo.environment["LIDLESS_HOME"] { return URL(fileURLWithPath: override) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lidless")
    }()
    static var holds: URL { support.appendingPathComponent("holds") }
    static let pmset = "/usr/bin/pmset"
    static let sudoers = "/etc/sudoers.d/lidless"
    static let cliLink = "/usr/local/bin/lidless"
}

// MARK: - Holds

/// A hold keeps the Mac awake while its process is alive. Claude Code hooks and `lidless run` write these.
struct Hold: Codable, Equatable {
    var id: String
    var pid: Int32
    var label: String
    var kind: String          // "hook" or "run"
    var started: Double

    var startedDate: Date { Date(timeIntervalSince1970: started) }
}

enum HoldStore {
    static func ensureDir() {
        try? FileManager.default.createDirectory(at: Paths.holds, withIntermediateDirectories: true)
    }

    static func url(for id: String) -> URL {
        let safe = id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return Paths.holds.appendingPathComponent(String(safe) + ".json")
    }

    static func write(_ hold: Hold) {
        ensureDir()
        let enc = JSONEncoder()
        if let data = try? enc.encode(hold) { try? data.write(to: url(for: hold.id), options: .atomic) }
    }

    static func remove(id: String) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Reads every hold, deleting the ones whose process has exited.
    static func live() -> [Hold] {
        ensureDir()
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.holds, includingPropertiesForKeys: nil)) ?? []
        var out: [Hold] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let hold = try? JSONDecoder().decode(Hold.self, from: data) else {
                try? FileManager.default.removeItem(at: file); continue
            }
            if isAlive(hold.pid) { out.append(hold) } else { try? FileManager.default.removeItem(at: file) }
        }
        return out.sorted { $0.started < $1.started }
    }
}

func isAlive(_ pid: Int32) -> Bool {
    guard pid > 0 else { return false }
    return kill(pid, 0) == 0 || errno == EPERM
}

/// Parent pid and short command name of a process, via sysctl.
func procInfo(_ pid: Int32) -> (ppid: Int32, name: String)? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw -> String in
        let bytes = raw.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
    return (info.kp_eproc.e_ppid, name)
}

/// The agent process that launched this hook: the first ancestor that is not a shell.
func agentAncestor() -> Int32 {
    let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env", "Lidless", "lidless"]
    var pid = getppid()
    for _ in 0..<6 {
        guard let info = procInfo(pid) else { break }
        if !shells.contains(info.name) { return pid }
        if info.ppid <= 1 { break }
        pid = info.ppid
    }
    return getppid()
}

// MARK: - Process scanning

struct Proc {
    var pid: Int32
    var ppid: Int32
    var cpu: Double
    var args: String
}

enum Agents {
    /// Executable names Lidless recognises, and how they show in the menu.
    static let known: [String: String] = [
        "claude": "Claude Code",
        "codex": "Codex",
        "gemini": "Gemini CLI",
        "aider": "Aider",
        "opencode": "OpenCode",
        "cursor-agent": "Cursor Agent",
        "goose": "Goose",
        "amp": "Amp",
        "qwen": "Qwen Code",
        "crush": "Crush",
        "droid": "Droid",
        "copilot": "Copilot CLI",
        "kiro-cli": "Kiro",
    ]
    static let runtimes: Set<String> = ["node", "bun", "deno", "python", "python3"]

    /// Returns the agent key for a command line, or nil.
    /// Long-running helpers that share an agent's executable but never do agent work.
    static let helperFlags = ["--chrome-native-host", "mcp serve", "mcp-server", "--acp"]

    static func match(_ args: String) -> String? {
        if helperFlags.contains(where: args.contains) { return nil }
        let tokens = args.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = tokens.first else { return nil }
        var name = (first as NSString).lastPathComponent
        if runtimes.contains(name) || name.hasPrefix("python3.") {
            guard let script = tokens.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return nil }
            name = (script as NSString).lastPathComponent
        }
        if name.hasSuffix(".js") || name.hasSuffix(".mjs") { name = String(name.split(separator: ".").first ?? "") }
        return known[name] == nil ? nil : name
    }

    static func parsePS(_ text: String) -> [Proc] {
        var out: [Proc] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2].replacingOccurrences(of: ",", with: ".")) else { continue }
            out.append(Proc(pid: pid, ppid: ppid, cpu: cpu, args: String(parts[3])))
        }
        return out
    }

    static func snapshot() -> [Proc] {
        parsePS(run("/bin/ps", ["-axo", "pid=,ppid=,%cpu=,args="]).output)
    }
}

/// One detected agent process with the CPU used by it and everything it spawned.
struct AgentProc {
    var pid: Int32
    var key: String
    var treeCPU: Double
}

func findAgents(in procs: [Proc]) -> [AgentProc] {
    var children: [Int32: [Proc]] = [:]
    var byPid: [Int32: Proc] = [:]
    for p in procs { children[p.ppid, default: []].append(p); byPid[p.pid] = p }
    func treeCPU(_ pid: Int32, depth: Int = 0) -> Double {
        guard depth < 32 else { return 0 }
        return (byPid[pid]?.cpu ?? 0) + (children[pid] ?? []).reduce(0) { $0 + treeCPU($1.pid, depth: depth + 1) }
    }
    var out: [AgentProc] = []
    for p in procs {
        guard let key = Agents.match(p.args) else { continue }
        // Skip wrappers: an agent whose parent is the same agent is counted once, at the top.
        if let parent = byPid[p.ppid], Agents.match(parent.args) == key { continue }
        out.append(AgentProc(pid: p.pid, key: key, treeCPU: treeCPU(p.pid)))
    }
    return out
}

// MARK: - Shell helpers

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = args
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    task.standardInput = FileHandle.nullDevice
    do { try task.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return (task.terminationStatus, String(decoding: data, as: UTF8.self))
}

// MARK: - Power

enum Power {
    /// The sudoers rule Lidless installs. It allows exactly these two commands and nothing else.
    static func sudoersLine(user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: \(Paths.pmset) -a disablesleep 1, \(Paths.pmset) -a disablesleep 0\n"
    }

    static var isAuthorized: Bool {
        FileManager.default.fileExists(atPath: Paths.sudoers)
    }

    @discardableResult
    static func setLidSleepDisabled(_ disabled: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", Paths.pmset, "-a", "disablesleep", disabled ? "1" : "0"]).status == 0
    }

    static var lidSleepDisabled: Bool {
        let out = run(Paths.pmset, ["-g"]).output
        return out.split(separator: "\n").contains { line in
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
        }
    }

    static var lidClosed: Bool {
        run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "1"]).output
            .contains("\"AppleClamshellState\" = Yes")
    }

    static func sleepNow() { run(Paths.pmset, ["sleepnow"]) }

    /// Battery percent and whether the Mac is running on battery. nil on desktops.
    static func battery() -> (percent: Int, onBattery: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let cur = desc[kIOPSCurrentCapacityKey] as? Int, let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let state = desc[kIOPSPowerSourceStateKey] as? String
            return (cur * 100 / max, state == kIOPSBatteryPowerValue)
        }
        return nil
    }
}

/// Keeps idle sleep away while the lid is open. Lid-close sleep is handled by pmset.
final class IdleAssertion {
    private var id: IOPMAssertionID = 0
    private(set) var active = false

    func take(reason: String) {
        guard !active else { return }
        active = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id) == kIOReturnSuccess
    }

    func release() {
        guard active else { return }
        IOPMAssertionRelease(id)
        active = false
    }
}
