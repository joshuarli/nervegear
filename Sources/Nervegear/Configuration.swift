import Foundation

struct AppConfiguration {
    let shaderURL: URL
    let sceneURL: URL
    let materialsURL: URL
    let assetsURL: URL
    let sessionURL: URL
    let readyURL: URL?

    static func parse(arguments: [String], workingDirectory: URL) throws -> AppConfiguration {
        var options: [String: String] = [:]
        var index = 1

        while index < arguments.count {
            let key = arguments[index]
            guard ["--shader", "--scene", "--materials", "--session", "--ready-file"].contains(key) else {
                throw ConfigurationError.usage("unknown option: \(key)")
            }
            guard index + 1 < arguments.count else {
                throw ConfigurationError.usage("missing value for \(key)")
            }
            guard options[key] == nil else {
                throw ConfigurationError.usage("option repeated: \(key)")
            }
            options[key] = arguments[index + 1]
            index += 2
        }

        func resolve(_ option: String, defaultPath: String?) -> URL? {
            guard let path = options[option] ?? defaultPath else { return nil }
            let url = URL(fileURLWithPath: path, relativeTo: workingDirectory)
            return url.standardizedFileURL
        }

        guard let shaderURL = resolve("--shader", defaultPath: "Shaders/World.metal"),
              let sceneURL = resolve("--scene", defaultPath: "Scenes/world.json"),
              let materialsURL = resolve("--materials", defaultPath: "Materials/default.json"),
              let sessionURL = resolve("--session", defaultPath: ".work/dev/session.json") else {
            throw ConfigurationError.usage("could not resolve application paths")
        }

        return AppConfiguration(
            shaderURL: shaderURL,
            sceneURL: sceneURL,
            materialsURL: materialsURL,
            assetsURL: workingDirectory.appendingPathComponent("Assets/Objects", isDirectory: true).standardizedFileURL,
            sessionURL: sessionURL,
            readyURL: resolve("--ready-file", defaultPath: nil)
        )
    }
}

enum ConfigurationError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .usage(let detail):
            return "\(detail)\nUsage: Nervegear [--shader PATH] [--scene PATH] [--materials PATH] [--session PATH] [--ready-file PATH]"
        }
    }
}
