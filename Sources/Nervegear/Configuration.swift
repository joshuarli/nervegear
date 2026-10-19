import Foundation

struct AppConfiguration {
    let shaderURL: URL
    let sceneURL: URL
    let materialsURL: URL
    let assetsURL: URL
    let playerModelURL: URL
    let playerMaterialsURL: URL
    let playerTextureURLs: [URL]
    let primitivePlayer: Bool
    let sessionURL: URL
    let readyURL: URL?
    let screenshotURL: URL
    let screenshotOnLaunch: Bool

    static func parse(arguments: [String], workingDirectory: URL) throws -> AppConfiguration {
        var options: [String: String] = [:]
        var screenshotOnLaunch = false
        var primitivePlayer = false
        var index = 1

        while index < arguments.count {
            let key = arguments[index]
            if key == "--capture-on-launch" {
                guard !screenshotOnLaunch else {
                    throw ConfigurationError.usage("option repeated: \(key)")
                }
                screenshotOnLaunch = true
                index += 1
                continue
            }
            if key == "--primitive-player" {
                guard !primitivePlayer else {
                    throw ConfigurationError.usage("option repeated: \(key)")
                }
                primitivePlayer = true
                index += 1
                continue
            }
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

        let assetsURL = workingDirectory.appendingPathComponent("Assets/Objects", isDirectory: true).standardizedFileURL
        let playerDirectory = assetsURL.appendingPathComponent("Characters/Asuna", isDirectory: true)

        return AppConfiguration(
            shaderURL: shaderURL,
            sceneURL: sceneURL,
            materialsURL: materialsURL,
            assetsURL: assetsURL,
            playerModelURL: playerDirectory.appendingPathComponent("asuna.obj", isDirectory: false),
            playerMaterialsURL: playerDirectory.appendingPathComponent("materials.json", isDirectory: false),
            playerTextureURLs: [
                playerDirectory.appendingPathComponent("Textures/badan.png", isDirectory: false),
                playerDirectory.appendingPathComponent("Textures/wajah.png", isDirectory: false)
            ],
            primitivePlayer: primitivePlayer,
            sessionURL: sessionURL,
            readyURL: resolve("--ready-file", defaultPath: nil),
            screenshotURL: workingDirectory.appendingPathComponent(".work/tmp/scene.png").standardizedFileURL,
            screenshotOnLaunch: screenshotOnLaunch
        )
    }
}

enum ConfigurationError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .usage(let detail):
            return "\(detail)\nUsage: Nervegear [--shader PATH] [--scene PATH] [--materials PATH] [--session PATH] [--ready-file PATH] [--capture-on-launch] [--primitive-player]"
        }
    }
}
