// Adds or removes Lidless's hooks for agents that support them (Claude Code, Codex CLI),
// without touching anything else in their config files.
import Foundation

struct HookTarget {
    var key: String                                  // agent key, as in Agents.known
    var label: String
    var file: URL                                    // JSON file holding a top-level "hooks" object
    var events: [(name: String, action: String)]

    var home: URL { file.deletingLastPathComponent() }

    static let userHome = FileManager.default.homeDirectoryForCurrentUser

    static let claude = HookTarget(
        key: "claude", label: "Claude Code",
        file: userHome.appendingPathComponent(".claude/settings.json"),
        events: [("UserPromptSubmit", "start"), ("Stop", "stop"), ("SessionEnd", "stop")])

    static let codex = HookTarget(
        key: "codex", label: "Codex",
        file: userHome.appendingPathComponent(".codex/hooks.json"),
        events: [("UserPromptSubmit", "start"), ("Stop", "stop"), ("Interrupt", "stop"), ("SessionEnd", "stop")])

    static let all = [claude, codex]

    static func target(for key: String) -> HookTarget { all.first { $0.key == key } ?? claude }
}

enum Hooks {
    static let marker = "Lidless.app/Contents/MacOS/Lidless' hook"

    static func load(_ t: HookTarget) -> [String: Any] {
        guard let data = try? Data(contentsOf: t.file),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    static func isInstalled(_ t: HookTarget) -> Bool { isInstalled(in: load(t), events: t.events) }

    static func isInstalled(in settings: [String: Any], events: [(name: String, action: String)] = HookTarget.claude.events) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { ev in
            ((hooks[ev.name] as? [[String: Any]]) ?? []).contains(where: isOurs)
        }
    }

    static func command(binary: String, action: String, key: String) -> String {
        "'\(binary.replacingOccurrences(of: "'", with: "'\\''"))' hook \(action) \(key)"
    }

    /// Installed, and every hook is exactly the command this copy of the app would write.
    static func isCurrent(_ t: HookTarget, binary: String) -> Bool {
        let settings = load(t)
        guard isInstalled(in: settings, events: t.events), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return t.events.allSatisfy { ev in
            let expected = command(binary: binary, action: ev.action, key: t.key)
            return ((hooks[ev.name] as? [[String: Any]]) ?? []).filter(isOurs).allSatisfy { group in
                ((group["hooks"] as? [[String: Any]]) ?? []).allSatisfy { ($0["command"] as? String) == expected }
            }
        }
    }

    static func isOurs(_ group: [String: Any]) -> Bool {
        ((group["hooks"] as? [[String: Any]]) ?? []).contains { (($0["command"] as? String) ?? "").contains(marker) }
    }

    /// Pure merge, so the self-test can check it without a real settings file.
    static func merged(_ settings: [String: Any], binary: String, install: Bool, target t: HookTarget = .claude) -> [String: Any] {
        var out = settings
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        for ev in t.events {
            var groups = ((hooks[ev.name] as? [[String: Any]]) ?? []).filter { !isOurs($0) }
            if install {
                groups.append(["hooks": [["type": "command", "command": command(binary: binary, action: ev.action, key: t.key), "timeout": 5]]])
            }
            if groups.isEmpty { hooks.removeValue(forKey: ev.name) } else { hooks[ev.name] = groups }
        }
        if hooks.isEmpty { out.removeValue(forKey: "hooks") } else { out["hooks"] = hooks }
        return out
    }

    /// Writes the change, keeping a one-time backup of the original file. Does nothing if the agent isn't installed.
    static func set(_ t: HookTarget, installed: Bool, binary: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: t.home.path) else { return }
        let backup = t.file.appendingPathExtension("lidless-backup")
        if fm.fileExists(atPath: t.file.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: t.file, to: backup)
        }
        var current: [String: Any] = [:]
        if let data = try? Data(contentsOf: t.file), !data.isEmpty {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            current = obj
        }
        let next = merged(current, binary: binary, install: installed, target: t)
        if !fm.fileExists(atPath: t.file.path) && !installed { return }
        let data = try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        try data.write(to: t.file, options: .atomic)
        if t.key == "codex" && installed { try CodexFeature.enable() }
    }
}

/// Codex only runs hooks with `codex_hooks = true` under [features] in ~/.codex/config.toml.
enum CodexFeature {
    static var config: URL { HookTarget.codex.home.appendingPathComponent("config.toml") }

    static func enabled(in text: String) -> Bool {
        var inFeatures = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inFeatures = line == "[features]"; continue }
            if inFeatures, line.replacingOccurrences(of: " ", with: "") == "codex_hooks=true" { return true }
        }
        return false
    }

    /// The config with the flag set: added to an existing [features] table, or a new table appended.
    static func withFlag(_ text: String) -> String {
        if enabled(in: text) { return text }
        var lines = text.components(separatedBy: "\n")
        if let i = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            var j = i + 1
            while j < lines.count, !lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                if lines[j].replacingOccurrences(of: " ", with: "").hasPrefix("codex_hooks=") {
                    lines[j] = "codex_hooks = true"
                    return lines.joined(separator: "\n")
                }
                j += 1
            }
            lines.insert("codex_hooks = true", at: i + 1)
            return lines.joined(separator: "\n")
        }
        let sep = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
        return text + sep + "\n[features]\ncodex_hooks = true\n"
    }

    static func enable() throws {
        let fm = FileManager.default
        let text = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
        let next = withFlag(text)
        guard next != text else { return }
        let backup = config.appendingPathExtension("lidless-backup")
        if fm.fileExists(atPath: config.path), !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: config, to: backup) }
        try next.write(to: config, atomically: true, encoding: .utf8)
    }
}
