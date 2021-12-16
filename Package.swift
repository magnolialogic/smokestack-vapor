// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "smokestack-vapor",
    platforms: [
       .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.53.0"),
		.package(url: "https://github.com/vapor/redis.git", from: "4.5.0"),
		.package(url: "https://github.com/vapor/apns.git", from: "2.2.0"),
		.package(url: "https://github.com/magnolialogic/smokestack-core.git", .branch("main"))
    ],
    targets: [
        .target(
            name: "Smokestack",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
				.product(name: "Redis", package: "redis"),
				.product(name: "APNS", package: "apns"),
				.product(name: "CoreSmokestack", package: "smokestack-core")
            ],
            swiftSettings: [
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .executableTarget(name: "Run", dependencies: [.target(name: "Smokestack")]),
        .testTarget(name: "SmokestackTests", dependencies: [
            .target(name: "Smokestack"),
            .product(name: "XCTVapor", package: "vapor")
        ])
    ]
)
