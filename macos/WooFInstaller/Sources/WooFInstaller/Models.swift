import Foundation

enum InstallerConstants {
    static let expectedBundleID = "app.kinopad.KinoPad"
    static let githubRepository = "thefuckerguy/kinopub"
    static let githubURL = URL(string: "https://github.com/thefuckerguy/kinopub")!
    static let appStoreConnectURL = URL(string: "https://appstoreconnect.apple.com/apps")!
    static let developerEnrollmentURL = URL(string: "https://developer.apple.com/programs/enroll/")!
}

struct IOSDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let model: String
    let osVersion: String
    let connection: String
    let developerModeEnabled: Bool

    var isWireless: Bool {
        connection == "localNetwork"
    }

    var detail: String {
        [model, osVersion.isEmpty ? nil : "iOS \(osVersion)", connectionLabel]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var connectionLabel: String? {
        switch connection {
        case "localNetwork": return "Wi‑Fi"
        case "usb", "wired": return "USB"
        case "sameMachine": return "локально"
        default: return connection.isEmpty ? nil : connection
        }
    }
}

struct DeviceListDocument: Decodable {
    let result: DeviceListResult
}

struct DeviceListResult: Decodable {
    let devices: [RawDevice]
}

struct RawDevice: Decodable {
    let identifier: String
    let visibilityClass: String?
    let properties: DeviceProperties

    var installerDevice: IOSDevice? {
        guard visibilityClass != "simulators",
              properties.hardware.platform == "iOS",
              properties.connection.state == "connected" else { return nil }

        let commandID = properties.hardware.udid ?? identifier
        return IOSDevice(
            id: commandID,
            name: properties.state.name ?? properties.hardware.marketingName ?? "iPhone/iPad",
            model: properties.hardware.marketingName ?? properties.hardware.productType ?? "iOS‑устройство",
            osVersion: properties.software.osVersionNumber?.stringValue ?? "",
            connection: properties.connection.transportType ?? "",
            developerModeEnabled: properties.state.developerModeStatus?.enabled != nil
        )
    }
}

struct DeviceProperties: Decodable {
    let hardware: DeviceHardware
    let software: DeviceSoftware
    let state: DeviceState
    let connection: DeviceConnection
}

struct DeviceHardware: Decodable {
    let marketingName: String?
    let platform: String?
    let productType: String?
    let udid: String?
}

struct DeviceSoftware: Decodable {
    let osVersionNumber: DeviceOSVersion?
}

struct DeviceOSVersion: Decodable {
    let stringValue: String?
}

struct DeviceState: Decodable {
    let name: String?
    let developerModeStatus: DeveloperModeStatus?
}

struct DeveloperModeStatus: Decodable {
    let enabled: DeveloperModeValue?
}

struct DeveloperModeValue: Decodable {
    let mode: Int?
}

struct DeviceConnection: Decodable {
    let state: String?
    let transportType: String?
}

struct InstalledAppsDocument: Decodable {
    let result: InstalledAppsResult
}

struct InstalledAppsResult: Decodable {
    let apps: [InstalledApp]
}

struct InstalledApp: Decodable {
    let bundleIdentifier: String
    let version: String?
    let bundleVersion: String?
}

struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft, prerelease, assets
    }

    var ipaAsset: GitHubReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".ipa") }
    }
}

struct GitHubReleaseAsset: Decodable, Equatable {
    let name: String
    let size: Int64
    let browserDownloadURL: URL
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case browserDownloadURL = "browser_download_url"
    }
}

struct IPAInspection: Equatable {
    let displayName: String
    let bundleID: String
    let version: String
    let build: String
    let teamName: String?
    let expirationDate: Date?
    let provisionedDevices: Set<String>
    let provisionsAllDevices: Bool

    func supports(deviceID: String) -> Bool {
        provisionsAllDevices || provisionedDevices.contains(deviceID)
    }
}

struct AppVersion: Comparable, Equatable {
    private let components: [Int]

    init(_ raw: String) {
        components = raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(whereSeparator: { !$0.isNumber })
            .map { Int($0) ?? 0 }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
