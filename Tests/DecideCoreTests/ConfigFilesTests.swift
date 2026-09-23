import Testing

@testable import DecideCore

/// The paths of one run, so a test names them once.
private let near = "/home/u/proj/sub/.decide/config"
private let far = "/home/u/proj/.decide/config"
private let xdg = "/home/u/.config/decide/config"
private let dotHome = "/home/u/.decide/config"

/// Two project files, nearest first, and the two home files.
private let allPaths = ConfigPaths(project: [near, far], home: [xdg, dotHome])

/// The paths for a working directory and an environment.
private func paths(_ currentDirectory: String, _ environment: [String: String]) -> ConfigPaths {
    ConfigFiles.paths(currentDirectory: currentDirectory, environment: environment)
}

/// A reader over a map of path to text. A path in `unreadable` or `notUTF8`
/// throws that reason; a path in neither and not in the map has no file.
private func reader(
    files: [String: String],
    unreadable: Set<String> = [],
    notUTF8: Set<String> = []
) -> (String) throws(ConfigReadError) -> String? {
    { (path: String) throws(ConfigReadError) -> String? in
        if unreadable.contains(path) { throw .unreadable }
        if notUTF8.contains(path) { throw .notUTF8 }
        return files[path]
    }
}

@Suite("ConfigFiles")
struct ConfigFilesTests {
    @Test("A working directory under HOME walks up and stops before it")
    func walkUnderHome() {
        #expect(
            paths("/home/u/proj/sub/deep", ["HOME": "/home/u"])
                == ConfigPaths(
                    project: [
                        "/home/u/proj/sub/deep/.decide/config",
                        near,
                        far,
                    ],
                    home: [xdg, dotHome]
                )
        )
    }

    @Test("The home directory itself yields no project file")
    func workingDirectoryIsHome() {
        #expect(
            paths("/home/u", ["HOME": "/home/u"])
                == ConfigPaths(project: [], home: [xdg, dotHome])
        )
    }

    @Test("A working directory outside HOME walks to the root")
    func walkOutsideHome() {
        #expect(
            paths("/srv/app/x", ["HOME": "/home/u"])
                == ConfigPaths(
                    project: [
                        "/srv/app/x/.decide/config",
                        "/srv/app/.decide/config",
                        "/srv/.decide/config",
                        "/.decide/config",
                    ],
                    home: [xdg, dotHome]
                )
        )
    }

    @Test("An unset or blank HOME gives no home file and a walk to the root")
    func withoutHome() {
        let expected = ConfigPaths(
            project: [
                "/home/u/proj/.decide/config",
                "/home/u/.decide/config",
                "/home/.decide/config",
                "/.decide/config",
            ],
            home: []
        )
        #expect(paths("/home/u/proj", [:]) == expected)
        #expect(paths("/home/u/proj", ["HOME": "  "]) == expected)
    }

    @Test("XDG_CONFIG_HOME moves the first home file")
    func xdgConfigHome() {
        #expect(
            paths("/home/u", ["HOME": "/home/u", "XDG_CONFIG_HOME": "/xdg"])
                == ConfigPaths(project: [], home: ["/xdg/decide/config", dotHome])
        )
    }

    @Test("A blank or relative XDG_CONFIG_HOME falls back to ~/.config")
    func xdgConfigHomeFallback() {
        let expected = ConfigPaths(project: [], home: [xdg, dotHome])
        #expect(paths("/home/u", ["HOME": "/home/u", "XDG_CONFIG_HOME": " "]) == expected)
        // The XDG spec ignores a path that is not absolute.
        #expect(paths("/home/u", ["HOME": "/home/u", "XDG_CONFIG_HOME": "xdg"]) == expected)
    }

    @Test("A HOME with a trailing slash still stops the walk")
    func homeWithTrailingSlash() {
        #expect(
            paths("/home/u/proj", ["HOME": "/home/u/"])
                == ConfigPaths(project: [far], home: [xdg, dotHome])
        )
    }

    @Test("The nearest file wins per key")
    func nearestWins() throws {
        let config = try ConfigFiles.load(
            paths: allPaths,
            read: reader(files: [
                near: #"DECIDE_MODEL = "typesafe:jev-latest""#,
                far: #"DECIDE_MODEL = "openrouter:typesafe/jev-1.13""#,
            ])
        )
        #expect(config == ["DECIDE_MODEL": "typesafe:jev-latest"])
    }

    @Test("A key only the farthest file sets is used")
    func farthestKey() throws {
        let config = try ConfigFiles.load(
            paths: allPaths,
            read: reader(files: [
                near: #"DECIDE_MODEL = "typesafe:jev-latest""#,
                dotHome: #"DECIDE_MODEL_API_KEY = "k""#,
            ])
        )
        #expect(config == ["DECIDE_MODEL": "typesafe:jev-latest", "DECIDE_MODEL_API_KEY": "k"])
    }

    @Test("A project key wins over the same key in a home file")
    func projectOverHome() throws {
        let config = try ConfigFiles.load(
            paths: allPaths,
            read: reader(files: [
                far: #"DECIDE_MODEL = "typesafe:jev-latest""#,
                xdg: """
                    DECIDE_MODEL = "openrouter:typesafe/jev-1.13"
                    DECIDE_MODEL_API_KEY = "k"
                    """,
            ])
        )
        #expect(config == ["DECIDE_MODEL": "typesafe:jev-latest", "DECIDE_MODEL_API_KEY": "k"])
    }

    @Test("A path with no file is skipped")
    func missingFilesSkipped() throws {
        let config = try ConfigFiles.load(
            paths: allPaths,
            read: reader(files: [far: #"DECIDE_MODEL = "typesafe:jev-latest""#])
        )
        #expect(config == ["DECIDE_MODEL": "typesafe:jev-latest"])
        #expect(try ConfigFiles.load(paths: allPaths, read: reader(files: [:])) == [:])
    }

    @Test("A file that does not read names itself")
    func unreadableFile() {
        #expect(throws: ConfigError(path: far, line: 0, problem: "cannot read the file")) {
            try ConfigFiles.load(paths: allPaths, read: reader(files: [:], unreadable: [far]))
        }
    }

    @Test("A file that is not UTF-8 names itself")
    func notUTF8File() {
        #expect(throws: ConfigError(path: xdg, line: 0, problem: "is not valid UTF-8")) {
            try ConfigFiles.load(paths: allPaths, read: reader(files: [:], notUTF8: [xdg]))
        }
    }

    @Test("A parse error carries the file's path and line")
    func parseError() {
        #expect(
            throws: ConfigError(
                path: far,
                line: 2,
                problem: ConfigFile.unknownKeyProblem("DECIDE_MODE")
            )
        ) {
            try ConfigFiles.load(
                paths: allPaths,
                read: reader(files: [
                    far: """
                        # the model
                        DECIDE_MODE = "typesafe:jev-latest"
                        """
                ])
            )
        }
    }

    @Test("The key in a project file is an error at its line")
    func keyInProjectFile() {
        #expect(
            throws: ConfigError(
                path: near,
                line: 2,
                problem: """
                    DECIDE_MODEL_API_KEY is allowed only in the home config, \
                    not in a project's
                    """
            )
        ) {
            try ConfigFiles.load(
                paths: allPaths,
                read: reader(files: [
                    near: """
                        DECIDE_MODEL = "typesafe:jev-latest"
                        DECIDE_MODEL_API_KEY = "k"
                        """
                ])
            )
        }
    }

    @Test("The key is taken from either home file")
    func keyInEitherHomeFile() throws {
        for path in [xdg, dotHome] {
            let config = try ConfigFiles.load(
                paths: allPaths,
                read: reader(files: [path: #"DECIDE_MODEL_API_KEY = "k""#])
            )
            #expect(config == ["DECIDE_MODEL_API_KEY": "k"], "\(path)")
        }
    }

    @Test("The two home files merge, the first one winning")
    func homeFilesMerge() throws {
        let config = try ConfigFiles.load(
            paths: allPaths,
            read: reader(files: [
                xdg: #"DECIDE_MODEL_API_KEY = "first""#,
                dotHome: """
                    DECIDE_MODEL = "typesafe:jev-latest"
                    DECIDE_MODEL_API_KEY = "second"
                    """,
            ])
        )
        #expect(config == ["DECIDE_MODEL": "typesafe:jev-latest", "DECIDE_MODEL_API_KEY": "first"])
    }

    @Test("A variable the environment sets wins over the config")
    func environmentWins() {
        #expect(
            ConfigFiles.environment(
                ["DECIDE_MODEL": "openrouter:typesafe/jev-1.13"],
                over: ["DECIDE_MODEL": "typesafe:jev-latest"]
            ) == ["DECIDE_MODEL": "openrouter:typesafe/jev-1.13"]
        )
    }

    @Test("A blank or unset variable takes the config's value")
    func blankFallsThrough() {
        let config = ["DECIDE_MODEL": "typesafe:jev-latest"]
        #expect(ConfigFiles.environment(["DECIDE_MODEL": " \n"], over: config) == config)
        #expect(ConfigFiles.environment([:], over: config) == config)
    }

    @Test("Unrelated variables pass through untouched")
    func unrelatedVariables() {
        #expect(
            ConfigFiles.environment(
                ["HOME": "/home/u", "PATH": "/bin"],
                over: ["DECIDE_MODEL_API_KEY": "k"]
            ) == ["HOME": "/home/u", "PATH": "/bin", "DECIDE_MODEL_API_KEY": "k"]
        )
    }

    @Test("An empty config leaves the environment alone")
    func emptyConfig() {
        let environment = ["DECIDE_MODEL": "typesafe:jev-latest", "PATH": "/bin"]
        #expect(ConfigFiles.environment(environment, over: [:]) == environment)
    }

    @Test("A config with no environment configures the model")
    func configReachesModelConfiguration() throws {
        let configuration = try ModelConfiguration(
            environment: ConfigFiles.environment(
                [:],
                over: [
                    ModelConfiguration.modelVariable: "typesafe:jev-latest",
                    ModelConfiguration.apiKeyVariable: "k",
                ]
            )
        )
        #expect(configuration.provider == .typesafe)
        #expect(configuration.model == "jev-latest")
        #expect(configuration.apiKey == "k")
    }
}
