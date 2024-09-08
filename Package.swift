// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AppsEngine",
    platforms: [
		.macOS(.v10_15),
		.iOS(.v13),
    ],
	products: [
		.library(name: "AppsEngine", targets: ["AppsEngine"]),
		.library(name: "MongoDBEngine", targets: ["MongoDBEngine"]),
	],
    dependencies: [
		.package(url: "https://github.com/apple/swift-statsd-client.git",
				 from: "1.0.0"),
		.package(url: "https://github.com/apple/swift-atomics.git",
				 .upToNextMajor(from: "1.2.0")),
		.package(url: "https://github.com/jpsim/Yams.git",
				 from: "4.0.6"),
		.package(url: "https://github.com/tsolomko/SWCompression",
				 from: "4.8.0"),
		.package(url: "https://github.com/vapor/fluent.git",
				 from: "4.4.0"),
		.package(url: "https://github.com/vapor/fluent-postgres-driver.git",
				 from: "2.2.2"),
		.package(url: "https://github.com/vapor/fluent-mongo-driver",
				 from: "1.0.2"),
		.package(url: "https://github.com/vapor/redis.git",
				 from: "4.0.0"),
		.package(url: "https://github.com/vapor/sql-kit.git",
				 from: "3.21.0"),
		.package(url: "https://github.com/vapor/vapor.git",
				 from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "AppsEngine",
            dependencies: [
				.product(name: "Fluent", package: "fluent"),
				.product(name: "Redis", package: "redis"),
				.product(name: "StatsdClient", package: "swift-statsd-client"),
				.product(name: "SQLKit", package: "sql-kit"),
				.product(name: "Vapor", package: "vapor"),
				"Yams",
				"SWCompression",
            ],
            swiftSettings: [
                // Enable better optimizations when building in Release configuration. Despite the use of
                // the `.unsafeFlags` construct required by SwiftPM, this flag is recommended for Release
                // builds. See <https://github.com/swift-server/guides/blob/main/docs/building.md#building-for-production> for details.
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
				.enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
		.target(name: "MongoDBEngine", dependencies: [
			.target(name: "AppsEngine"),
			.product(name: "FluentMongoDriver", package: "fluent-mongo-driver"),
		]),
        .executableTarget(
			name: "Example",
			dependencies: [
				.product(name: "FluentMongoDriver", package: "fluent-mongo-driver"),
				.product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
				.target(name: "AppsEngine"),
				.target(name: "MongoDBEngine"),
			],
			resources: [
				.process("config.yaml"),
				.copy("apps"),
			]
		),
        .testTarget(name: "EngineTests", dependencies: [
            .target(name: "AppsEngine"),
            .product(name: "XCTVapor", package: "vapor"),
        ]),
    ]
)
