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
import NIOConcurrencyHelpers

protocol RouteFinder {
	typealias ResolveFunc = (HandlerState, HTTPRequest) throws -> HTTPOutput
	init(_ registry: RouteRegistry<HTTPRequest, HTTPOutput>) throws
	subscript(uri: String) -> ResolveFunc? { get }
}

class RouteFinderRegExp: RouteFinder {
	typealias Matcher = (NSRegularExpression, ResolveFunc)
	let matchers: [Matcher]
	var cached1 = Atomic<Int>(value: -1)
	required init(_ registry: RouteRegistry<HTTPRequest, HTTPOutput>) throws {
		matchers = try registry.routes.filter {
			($0.path.components.contains("*") || $0.path.components.contains("**"))
		}.map { (try RouteFinderRegExp.regExp(for: $0.path), $0.resolve) }
	}
	subscript(uri: String) -> ResolveFunc? {
		let uriRange = NSRange(location: 0, length: uri.count)
		do {
			let c1 = cached1.load()
			if c1 != -1 {
				if let _ = matchers[c1].0.firstMatch(in: uri, range: uriRange) {
					return matchers[c1].1
				}
			}
		}
		for i in 0..<matchers.count {
			let matcher = matchers[i]
			guard let _ = matcher.0.firstMatch(in: uri, range: uriRange) else {
				continue
			}
			cached1.store(i)
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

class ReverseLookup: RouteFinder, CustomStringConvertible {
	var root = Entry()
	required init(_ registry: RouteRegistry<HTTPRequest, HTTPOutput>) throws {
		registry.routes.forEach {
			self.add($0.path.cleanedPath, $0.resolve)
		}
	}
	
	subscript(uri: String) -> ResolveFunc? {
		return find(uri)
	}
	
	var description: String {
		return root.description
	}
	class Entry: CustomStringConvertible {
		var description: String {
			if let r = rest {
				return "rest \(String(validatingUTF8: r.reversed())!)"
			}
			var s = "["
			if let c = children {
				for i in 0..<c.count {
					guard let e = c[i] else {
						continue
					}
					s += "\(i): \(e.description)\n"
				}
			}
			return s + "]"
		}
		var children: [Entry?]? = nil
		var payload: ResolveFunc? = nil
		var rest: [UInt8]? = nil
		func child(_ at: Int) -> Entry? {
			guard let c = children else {
				return nil
			}
			return c[at]
		}
		func add(_ chars: [UInt8], _ index: Array<UInt8>.Index, _ payload: @escaping ResolveFunc ) {
			if let r = rest, let p = self.payload {
				self.rest = nil
				self.payload = nil
				self.children = .init(repeating: nil, count: Int(UInt8.max))
				add(r, r.startIndex, p)
			}
			if index < chars.endIndex {
				let char = Int(chars[index])
				if let c = children {
					let e = c[char] ?? Entry()
					e.add(chars, chars.index(after: index), payload)
					children?[char] = e
				} else {
					self.payload = payload
					self.rest = Array(chars[index...])
				}
			} else {
				self.payload = payload
			}
		}
		func find(_ chars: [UInt8], _ index: Array<UInt8>.Index) -> ResolveFunc? {
			if index == chars.endIndex {
				return payload
			}
			if let r = rest {
				guard r == Array(chars[index...]) else {
					return nil
				}
				return payload
			}
			return children?[Int(chars[index])]?.find(chars, chars.index(after: index))
		}
	}
	func add(_ uri: String, _ payload: @escaping ResolveFunc) {
		add(Array(uri.utf8), payload)
	}
	func add(_ uri: [UInt8], _ payload: @escaping ResolveFunc) {
		root.add(uri.reversed(), uri.startIndex, payload)
	}
	func find(_ uri: String) -> ResolveFunc? {
		return find(Array(uri.utf8))
	}
	func find(_ uri: [UInt8]) -> ResolveFunc? {
		return root.find(uri.reversed(), uri.startIndex)
	}
}
