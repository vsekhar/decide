import Foundation

/// Where the config files are, how they merge, and how the result lays
/// under the environment.
///
/// The places are `.decide/config` in the working directory and in each
/// parent, then `<XDG_CONFIG_HOME or ~/.config>/decide/config` and
/// `~/.decide/config`. The walk stops before the home directory, or after
/// the root, whichever comes first. The nearest file wins per key: a key a
/// nearer file sets is not taken from a farther one. The environment wins
/// over every file, and a variable that is set but blank counts as unset.
///
/// Nothing here touches the disk. `paths` works on strings, and `load`
/// reads through a closure the caller gives it, so a test reads no real
/// file.
public enum ConfigFiles {
    /// The files to read, nearest first.
    ///
    /// `currentDirectory` is the working directory, as an absolute path; a
    /// relative one is read as if from the root. `environment` gives `HOME`
    /// and `XDG_CONFIG_HOME`. Every path is normalized, so a `HOME` with a
    /// trailing slash still stops the walk.
    public static func paths(
        currentDirectory: String,
        environment: [String: String]
    ) -> ConfigPaths {
        let home = nonBlank(environment["HOME"]).map(normalized)
        var project: [String] = []
        var directory = normalized(currentDirectory)
        while directory != home {
            project.append(joined(directory, ".decide/config"))
            if directory == "/" { break }
            directory = normalized(directory + "/..")
        }
        return ConfigPaths(project: project, home: homePaths(home: home, environment: environment))
    }

    /// Reads and merges the files, project first, and gives the pairs they
    /// set.
    ///
    /// `read` gives the text of a file, or nil when there is no file at the
    /// path. Every problem throws: a file that does not read, a file that
    /// is not UTF-8, a line the parser refuses, and
    /// `DECIDE_MODEL_API_KEY` in a project file, which the trust rule
    /// allows only in a home file.
    public static func load(
        paths: ConfigPaths,
        read: (String) throws(ConfigReadError) -> String?
    ) throws(ConfigError) -> [String: String] {
        var config: [String: String] = [:]
        for path in paths.project {
            try merge(path: path, isProject: true, into: &config, read: read)
        }
        for path in paths.home {
            try merge(path: path, isProject: false, into: &config, read: read)
        }
        return config
    }

    /// Lays the config under the environment.
    ///
    /// A variable the environment sets wins. One that is unset, or set but
    /// blank after trimming, takes the config's value. Every other variable
    /// passes through untouched.
    public static func environment(
        _ environment: [String: String],
        over config: [String: String]
    ) -> [String: String] {
        var result = environment
        for (key, value) in config where isBlank(result[key]) {
            result[key] = value
        }
        return result
    }

    /// The two home files, in order. None when `HOME` is unset or blank.
    /// `XDG_CONFIG_HOME` counts only when it is set, non-blank, and
    /// absolute, as the XDG spec says.
    private static func homePaths(home: String?, environment: [String: String]) -> [String] {
        guard let home else { return [] }
        let xdg = nonBlank(environment["XDG_CONFIG_HOME"])
            .flatMap { $0.hasPrefix("/") ? normalized($0) : nil }
        return [
            joined(xdg ?? joined(home, ".config"), "decide/config"),
            joined(home, ".decide/config"),
        ]
    }

    /// Reads one file and takes the keys no nearer file set. A file that is
    /// not there is skipped. `isProject` turns the trust rule on.
    private static func merge(
        path: String,
        isProject: Bool,
        into config: inout [String: String],
        read: (String) throws(ConfigReadError) -> String?
    ) throws(ConfigError) {
        let text: String?
        do {
            text = try read(path)
        } catch {
            throw ConfigError(path: path, line: 0, problem: problem(for: error))
        }
        guard let text else { return }
        for entry in try ConfigFile.parse(text, path: path) {
            if isProject, entry.key == ModelConfiguration.apiKeyVariable {
                throw ConfigError(path: path, line: entry.line, problem: keyInProjectProblem)
            }
            if config[entry.key] == nil { config[entry.key] = entry.value }
        }
    }

    /// What a key a project file may not set reports. A project file comes
    /// from a repository, so a key there is a leak waiting for a commit.
    private static let keyInProjectProblem = """
        \(ModelConfiguration.apiKeyVariable) is allowed only in the home config, \
        not in a project's
        """

    /// What a file the reader refused reports. The line is 0, so the
    /// message names the file alone.
    private static func problem(for error: ConfigReadError) -> String {
        switch error {
        case .unreadable: "cannot read the file"
        case .notUTF8: "is not valid UTF-8"
        }
    }

    /// The path with its `.`, `..`, and empty components resolved, from one
    /// leading slash. Lexical: it asks the filesystem nothing, so a path
    /// that is not there works in a test and a symbolic link is left alone.
    /// A `..` at the root stays at the root.
    private static func normalized(_ path: String) -> String {
        var components: [Substring] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }

    /// The directory and the tail, with one slash between them and none
    /// doubled at the root.
    private static func joined(_ directory: String, _ tail: String) -> String {
        directory == "/" ? "/" + tail : directory + "/" + tail
    }

    /// The trimmed value, or nil when the variable is unset or blank.
    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Whether the value is missing or holds nothing but whitespace, the
    /// state `ModelConfiguration` already counts as unset.
    private static func isBlank(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The files one run reads, nearest first.
public struct ConfigPaths: Equatable, Sendable {
    /// `.decide/config` in the working directory and in each parent,
    /// nearest first. Empty when the working directory is the home
    /// directory.
    public var project: [String]
    /// The home files: `<xdg>/decide/config`, then `<HOME>/.decide/config`.
    /// Empty when `HOME` is unset or blank.
    public var home: [String]

    public init(project: [String], home: [String]) {
        self.project = project
        self.home = home
    }
}

/// Why a file did not read. The reader gives nil when there is no file, so
/// these are the two ways a file that is there fails.
public enum ConfigReadError: Error, Equatable, Sendable {
    /// The bytes did not come back. A directory at the path counts here.
    case unreadable
    /// The bytes are not valid UTF-8.
    case notUTF8
}
