import Foundation

/// Developer tools' own cleanup commands. Each first shows what it would do with a dry run.
enum DevTools {
    // MARK: Homebrew

    struct BrewReport {
        let items: [String]
        let freeable: String?
    }

    static let brewPath = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    private static let brewEnv = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1", "HOMEBREW_NO_ANALYTICS": "1"]

    static func brewDryRun() -> BrewReport? {
        guard let brew = brewPath else { return nil }
        return parseBrew(Shell.run(brew, ["cleanup", "-s", "-n"], env: brewEnv).stdout)
    }

    static func parseBrew(_ text: String) -> BrewReport {
        let lines = text.split(separator: "\n").map(String.init)
        let items = lines.filter { $0.hasPrefix("Would remove:") }
            .map { $0.replacingOccurrences(of: "Would remove: ", with: "") }
        let freeable = lines.last { $0.contains("would free approximately") }
            .flatMap { line -> String? in
                guard let r = line.range(of: #"approximately ([\d.,]+\s?[KMGT]?B)"#, options: .regularExpression) else { return nil }
                return String(line[r]).replacingOccurrences(of: "approximately ", with: "")
            }
        return BrewReport(items: items, freeable: freeable)
    }

    static func brewCleanup() -> String? {
        guard let brew = brewPath else { return L("Homebrew not found.") }
        let out = Shell.run(brew, ["cleanup", "-s"], env: brewEnv)
        return out.status == 0 ? nil : out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Xcode simulators

    struct Simulator: Identifiable {
        let udid: String
        let name: String
        let runtime: String
        let size: Int64
        var id: String { udid }
    }

    static var hasSimctl: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Xcode.app") || FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools")
    }

    /// Simulators that belong to a runtime that is no longer installed (and can't be launched).
    static func unavailableSimulators() -> [Simulator] {
        guard hasSimctl else { return [] }
        let out = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"])
        guard out.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else { return [] }
        let base = Paths.home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        return devices.flatMap { runtime, list in
            list.compactMap { d -> Simulator? in
                guard let udid = d["udid"] as? String else { return nil }
                let shortRuntime = runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                return Simulator(udid: udid, name: d["name"] as? String ?? "?", runtime: shortRuntime,
                                 size: DiskScanner.allocatedSize(of: base.appendingPathComponent(udid)))
            }
        }
        .sorted { $0.size > $1.size }
    }

    static func deleteUnavailableSimulators() -> String? {
        let out = Shell.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])
        return out.status == 0 ? nil : out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Docker

    struct DockerUsage: Identifiable {
        let type: String
        let size: String
        let reclaimable: String
        var id: String { type }
    }

    struct DockerReport {
        let running: Bool
        let usage: [DockerUsage]
        /// Disk space used by Docker's virtual disk file (measurable even while the daemon is stopped).
        let diskImageSize: Int64
    }

    static let dockerPath = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker",
                             "/Applications/Docker.app/Contents/Resources/bin/docker"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    static let dockerDataURL = Paths.home
        .appendingPathComponent("Library/Containers/com.docker.docker/Data/vms")

    static func dockerReport() -> DockerReport? {
        guard let docker = dockerPath else { return nil }
        let imageSize = DiskScanner.allocatedSize(of: dockerDataURL)
        let out = Shell.run(docker, ["system", "df", "--format", "{{json .}}"])
        guard out.status == 0 else { return DockerReport(running: false, usage: [], diskImageSize: imageSize) }
        let usage = out.stdout.split(separator: "\n").compactMap { line -> DockerUsage? in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
            return DockerUsage(type: obj["Type"] as? String ?? "?", size: obj["Size"] as? String ?? "?",
                               reclaimable: obj["Reclaimable"] as? String ?? "?")
        }
        return DockerReport(running: true, usage: usage, diskImageSize: imageSize)
    }

    /// Stopped containers, unused networks, dangling images and the build cache. With `allImages`, all unused images.
    static func dockerPrune(allImages: Bool) -> String? {
        guard let docker = dockerPath else { return L("Docker not found.") }
        let out = Shell.run(docker, ["system", "prune", "-f"] + (allImages ? ["-a"] : []))
        return out.status == 0 ? nil : out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Projects

    /// Last change in the project a dependency folder belongs to (excluding the dependency folder itself).
    static func projectLastActivity(_ artifact: URL) -> Date? {
        let project = artifact.deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: [])) ?? []
        return items.filter { $0.lastPathComponent != artifact.lastPathComponent && $0.lastPathComponent != ".DS_Store" }
            .compactMap { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
            .max()
    }
}
