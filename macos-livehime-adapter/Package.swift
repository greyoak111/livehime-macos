// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveHimeAdapter",
    platforms: [.macOS(.v13)],
    products: [.library(name: "LiveHimeAdapter", targets: ["LiveHimeAdapter"])],
    targets: [
        .target(name: "LiveHimeAdapter"),
        .executableTarget(name: "LiveHimeMacApp", dependencies: ["LiveHimeAdapter"]),
        .testTarget(name: "LiveHimeAdapterTests", dependencies: ["LiveHimeAdapter"], resources: [.copy("Fixtures")])
    ]
)
