//
//  RouteDictionary.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-10-23.
//

import PerfectHTTP
import Foundation
import PerfectSQLite
import PerfectCRUD

protocol RouteFinder {
	typealias ResolveFunc = (HandlerState, HTTPRequest) throws -> HTTPOutput
	init(_ registry: RouteRegistry<HTTPRequest, HTTPOutput>) throws
	subscript(uri: String) -> ResolveFunc? { get }
}

class RouteFinderRegExp: RouteFinder {
	typealias Matcher = (NSRegularExpression, ResolveFunc)
	let matchers: [Matcher]
	required init(_ registry: RouteRegistry<HTTPRequest, HTTPOutput>) throws {
		matchers = try registry.routes.map { (try RouteFinderRegExp.regExp(for: $0.path), $0.resolve) }
	}
	subscript(uri: String) -> ResolveFunc? {
		let uriRange = NSRange(location: 0, length: uri.count)
		for matcher in matchers {
			guard let match = matcher.0.firstMatch(in: uri, range: uriRange) else {
				continue
			}
			// ranges/wildcards
			return matcher.1
		}
		return nil
	}
	static func regExp(for path: String) throws -> NSRegularExpression {
		let c = path.components
		let strs = c.map {
			comp -> String in
			switch comp {
			case "*":
				return "/([^/]*)"
			case "**":
				return "/(.*)"
			default:
				return "/\(comp)"
			}
		}
		return try NSRegularExpression(pattern: "^" + strs.joined(separator: "") + "$", options: NSRegularExpression.Options.caseInsensitive)
	}
}

class RouteFinderSQLite: RouteFinder {
	static func db() throws -> Database<SQLiteDatabaseConfiguration> {
		return Database(configuration: try SQLiteDatabaseConfiguration("file::memory:?cache=shared"))
	}
	struct RegRow: Codable {
		let key: String
		let routeIndex: Int
	}
	let routes: [RouteRegistry<HTTPRequest, HTTPOutput>.RouteItem]
	let db: Database<SQLiteDatabaseConfiguration>
	required init(_ registry: RouteRegistry<HTTPRequest, HTTPOutput>) throws {
		routes = registry.routes
		db = try RouteFinderSQLite.db()
		try db.create(RegRow.self, primaryKey: \.key)
		let table = db.table(RegRow.self)
		for i in 0..<routes.count {
			let row = RegRow(key: try RouteFinderSQLite.key(for: routes[i].path), routeIndex: i)
			try table.insert(row)
		}
	}
	
	subscript(uri: String) -> ResolveFunc? {
		guard let db = try? RouteFinderSQLite.db() else {
			return nil
		}
		guard let r = try? db.sql("select key, routeIndex from \(RegRow.CRUDTableName) where $1 like \"key\"", bindings: [("$1", .string(uri))] , RegRow.self).first,
			let reg = r else {
			return nil
		}
		return routes[reg.routeIndex].resolve
	}
	
	static func key(for path: String) throws -> String {
		let c = path.components
		let strs = c.map {
			comp -> String in
			switch comp {
			case "*":
				return "/%"
			case "**":
				return "/%"
			default:
				return "/\(comp)"
			}
		}
		return strs.joined(separator: "")
	}
}

class RouteFinderDictionary: RouteFinder {
	let dict: [String:ResolveFunc]
	required init(_ registry: RouteRegistry<HTTPRequest, HTTPOutput>) throws {
		dict = Dictionary(registry.routes.filter {
			!($0.path.components.contains("*") || $0.path.components.contains("**"))
		}.map {
			($0.path.cleanedPath, $0.resolve)
		}, uniquingKeysWith: {return $1})
	}
	subscript(uri: String) -> ResolveFunc? {
		return dict[uri]
	}
}

class RouteFinderDual: RouteFinder {
	let alpha: RouteFinder
	let beta: RouteFinder
	required init(_ registry: RouteRegistry<HTTPRequest, HTTPOutput>) throws {
		alpha = try RouteFinderDictionary(registry)
		beta = try RouteFinderRegExp(registry)
	}
	
	subscript(uri: String) -> ResolveFunc? {
		return alpha[uri] ?? beta[uri]
	}
}
