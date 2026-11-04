// Adds or removes Lidless's hooks in ~/.claude/settings.json without touching anything else there.
import Foundation

enum ClaudeHooks {
    static let marker = "Lidless.app/Contents/MacOS/Lidless' hook"
    static let events: [(name: String, action: String)] = [
        ("UserPromptSubmit", "start"), ("Stop", "stop"), ("SessionEnd", "stop"),
    ]

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    static var isInstalled: Bool { isInstalled(in: load()) }

    static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { ev in
            ((hooks[ev.name] as? [[String: Any]]) ?? []).contains(where: isOurs)
        }
    }

    static func isOurs(_ group: [String: Any]) -> Bool {
        ((group["hooks"] as? [[String: Any]]) ?? []).contains { (($0["command"] as? String) ?? "").contains(marker) }
    }

    /// Pure merge, so the self-test can check it without a real settings file.
    static func merged(_ settings: [String: Any], binary: String, install: Bool) -> [String: Any] {
        var out = settings
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        for ev in events {
            var groups = ((hooks[ev.name] as? [[String: Any]]) ?? []).filter { !isOurs($0) }
            if install {
                let command = "'\(binary.replacingOccurrences(of: "'", with: "'\\''"))' hook \(ev.action)"
                groups.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
            }
            if groups.isEmpty { hooks.removeValue(forKey: ev.name) } else { hooks[ev.name] = groups }
        }
        if hooks.isEmpty { out.removeValue(forKey: "hooks") } else { out["hooks"] = hooks }
        return out
    }

    /// Writes the change, keeping a one-time backup of the original file.
    static func set(installed: Bool, binary: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = settingsURL.appendingPathExtension("lidless-backup")
        if fm.fileExists(atPath: settingsURL.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: settingsURL, to: backup)
        }
        var current: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL), !data.isEmpty {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            current = obj
        }
        let next = merged(current, binary: binary, install: installed)
        let data = try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }
}
