// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CodexQuotaRing", platforms: [.macOS(.v14)], products: [
    .library(name: "QuotaCore", targets: ["QuotaCore"]),
    .executable(name: "CodexQuotaRing", targets: ["CodexQuotaRing"])
], targets: [
    .target(name: "QuotaCore", path: "Sources", exclude: ["App", "Views"], sources: ["Models", "Services"]),
    .executableTarget(name: "CodexQuotaRing", dependencies: ["QuotaCore"], path: "Sources", exclude: ["Models", "Services"], sources: ["App", "Views"]),
    .executableTarget(name: "QuotaProbe", dependencies: ["QuotaCore"], path: "Tools/QuotaProbe"),
    .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"], path: "Tests", resources: [.copy("Fixtures")])
])
