// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MoshCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MoshClientCore", targets: ["MoshClientCore"]),
        .library(name: "Prediction", targets: ["Prediction"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", branch: "main")
    ],
    targets: [
        .target(
            name: "MoshOCB",
            path: "Sources/MoshOCB",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MoshClientCore",
            dependencies: ["MoshOCB"],
            path: "Sources/MoshClientCore",
            exclude: ["README.md"],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "Prediction",
            dependencies: [
                "MoshClientCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/Prediction"
        )
    ]
)
