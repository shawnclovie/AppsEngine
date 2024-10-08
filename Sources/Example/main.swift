import AppsEngine
import Foundation
import FluentPostgresDriver
import Vapor

let resourceURL = Bundle.module.resourceURL!
// load config
let rawData = try Data(contentsOf: resourceURL.appendingPathComponent("config.yaml"))
let rawConfig = try EngineConfig.Format.yaml.decode(rawData)
// hard code config
let config = try await EngineConfig(
	workingDirectory: resourceURL, name: "example",
	debugFeatures: [Keys.all: .bool(true)],
	server: .init(port: 3000),
	timezone: TimeZone(identifier: "Asia/Shanghai")!,
	appSource: .init(localAppsPath: resourceURL.appendingPathComponent(EngineConfig.defaultLocalAppDirectory),
					 pullInterval: .zero),
	resource: .init(groups: [
		.init(
			id: Keys.default,
			databases: [
				.init(id: "sql", url: URL(string: "postgres://root:root@127.0.0.1:5432/shared")!),
			], redis: [
				.init(id: "shared", url: URL(string: "redis://127.0.0.1:6379")!),
			], objectStorages: [
				"main": try .init(
					name: "aws",
					cloud: .init(region: "cn-northwest-1",
								 secretID: "SECRET_IDENTITY",
								 secretKey: "SECRET_KEYFORTHEIDENTITY",
								 endpoint: nil),
					path: "dev/foo", baseURL: nil),
				"string_format": try .init(
					urlString: "/dev/foo?name=aws&region=cn-northwest-1&secret=SECRET_IDENTITY:SECRET_KEYFORTHEIDENTITY",
					baseURL: "https://dev.aws-s3/foo"),
			])
	]),
	loggers: [
		Keys.default: .init(outputers: [LogConsoleOutputer(minimalLevel: .trace, .stdout)]),
	],
	metric: .init(host: "127.0.0.1", port: 8125),
	rawData: rawConfig)
let engine = try await Engine(
	config: config,
	modules: [
		// Working modules
		TestModule(),
		RouteModule(),
	],
	appDetector: AppInfoHeaderAppDetector(),
	appUpdatorBuilder: { source, resources in
		if let storage = source.config {
			let provider = try await resources.objectStorageProvider(from: storage)
			return ZippedAppConfigUpdater(provider: provider)
		}
		if source.localAppsPath == nil {
			// make updator with fixed app data
			return AppConfigClosureUpdator { config, input in
				var result = AppConfigUpdateResult()
				var cors = CORSOptions()
				cors.allowedHeaders.append(contentsOf: [.init("X-Foo")])
				let appConfig = await AppConfigSet(core: .init(
					appID: "app1", appName: "AppLocalhost",
					hosts: [
						.init(host: "localhost", usage: .request),
						.init(host: "127.0.0.1"),
					],
					cors: cors,
					encryptions: [
						.init(id: "0123456789abcdef", secret: "0123456789abcdef0123456789abcdef"),
					]), modules: input.modules)
				await appConfig.add(environment: "foo", data: ["attr1": "jade"], modules: input.modules)
				await appConfig.add(environment: "bar", data: [:], modules: input.modules)
				await result.testDidFinish(appID: appConfig.core.appID, modifyTime: .utc, .success(appConfig))
				return result
			}
		}
		return AppConfigLocalUpdator()
	},
	appWillPrepareHook: { config in
	},
	requestProcessor: RouteModule.TestRequestProcessor(),
	databaseBuilder: { (config) in
		switch config.url.scheme {
		case "postgres":
			return try DatabaseConfigurationFactory.postgres(url: config.url).make()
		default:
			throw AnyError("unknown database type '\(config.url.scheme as Any)'")
		}
	},
	storageBuilder: {
		let path = resourceURL.appendingPathComponent("local_storage")
		if !FileManager.default.fileExists(atPath: path.path) {
			try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
		}
		return try ObjectStorageFileSystemProvider(source: $0, basepath: path)
	}
)
//try await ServiceRegister.initialize(engine.config, dataSource: ServerProcessProvider(engine))
try await engine.runServer(defaultMaxBodySize: "100mb")
