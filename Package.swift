// swift-tools-version:4.0

import PackageDescription

let package = Package(
	name: "PerfectHTTPCRUD",
	products: [
		.executable(name: "PerfectHTTPCRUD", targets: ["PerfectHTTPCRUDExe"]),
		.library(name: "HTTPCRUDLib", targets: ["HTTPCRUDLib"]),
	],
	dependencies: [
		.package(url: "https://github.com/PerfectlySoft/Perfect-Mustache.git", from: "3.0.0"),
		.package(url: "https://github.com/PerfectlySoft/PerfectLib.git", from: "3.0.0"),
		.package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", from: "3.0.0"),
		.package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", from: "1.0.0"),
		.package(url: "https://github.com/PerfectlySoft/Perfect-CURL.git", from: "3.0.0"),
		.package(url: "https://github.com/apple/swift-nio.git", from: "1.11.0")
	],
	targets: [
		.target(name: "PerfectHTTPCRUDExe", dependencies: ["HTTPCRUDLib", "PerfectSQLite"]),
		.target(name: "HTTPCRUDLib", dependencies: ["PerfectMustache", "PerfectLib", "PerfectCRUD", "NIOHTTP1"]),
		.testTarget(name: "HTTPCRUDLibTests", dependencies: ["HTTPCRUDLib", "PerfectSQLite", "PerfectCURL"]),
	]
)
