// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notchbox",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Notchbox", targets: ["Notchbox"])],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.3")
    ],
    targets: [
        .target(name: "NotchboxCore"),
        .executableTarget(
            name: "Notchbox",
            dependencies: ["NotchboxCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "NotchboxCoreTests", dependencies: ["NotchboxCore"])
    ],
    swiftLanguageModes: [.v5]
)
