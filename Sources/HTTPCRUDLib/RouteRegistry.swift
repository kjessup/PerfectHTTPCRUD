//
//  RouteRegistry.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-10-23.
//

import PerfectHTTP
import NIO

public enum RouteError: Error, CustomStringConvertible {
	case duplicatedRoutes([String])
	
	public var description: String {
		switch self {
		case .duplicatedRoutes(let r):
			return "Duplicated routes: \(r.joined(separator: ", "))"
		}
	}
}

//@dynamicMemberLookup
struct RouteRegistry<InType, OutType>: CustomStringConvertible {
	typealias ResolveFunc = (InType) throws -> OutType
	typealias Tuple = (String,ResolveFunc)
	let routes: [String:ResolveFunc]
	public var description: String {
		return routes.keys.sorted().joined(separator: "\n")
	}
	init(_ routes: [String:ResolveFunc]) {
		self.routes = routes
	}
	init(routes: [Tuple]) {
		self.init(Dictionary(uniqueKeysWithValues: routes))
	}
	func then<NewOut>(_ call: @escaping (OutType) throws -> NewOut) -> RouteRegistry<InType, NewOut> {
		return .init(routes: routes.map { let (p, f) = $0; return (p, {try call(f($0))}) })
	}
	func append<NewOut>(_ registry: RouteRegistry<OutType, NewOut>) -> RouteRegistry<InType, NewOut> {
		let a = routes.flatMap {
			(t: Tuple) -> [RouteRegistry<InType, NewOut>.Tuple] in
			let (itemPath, itemFnc) = t
			return registry.routes.map {
				(t: RouteRegistry<OutType, NewOut>.Tuple) -> RouteRegistry<InType, NewOut>.Tuple in
				let (subPath, subFnc) = t
				let (meth, path) = subPath.splitMethod
				let newPath = nil == meth ?
					itemPath.appending(component: path) :
					meth!.name + "://" + itemPath.splitMethod.1.appending(component: path)
				return (newPath, { try subFnc(itemFnc($0)) })
			}
		}
		return .init(routes: a)
	}
	func combine(_ registries: [RouteRegistry<InType, OutType>]) -> RouteRegistry<InType, OutType> {
		return .init(routes: routes + registries.flatMap { $0.routes })
	}
	func validate() throws {
		let paths = routes.map { $0.0 }.sorted()
		var dups = Set<String>()
		var last: String?
		paths.forEach {
			s in
			if s == last {
				dups.insert(s)
			}
			last = s
		}
		guard dups.isEmpty else {
			throw RouteError.duplicatedRoutes(Array(dups))
		}
	}
}

struct RouteValueBox<ValueType> {
	let state: HandlerState
	let value: ValueType
	init(_ state: HandlerState, _ value: ValueType) {
		self.state = state
		self.value = value
	}
}

typealias Future = EventLoopFuture

@dynamicMemberLookup
public struct Routes<InType, OutType> {
	typealias Registry = RouteRegistry<Future<RouteValueBox<InType>>, Future<RouteValueBox<OutType>>>
	let registry: Registry
	init(_ registry: Registry) {
		self.registry = registry
	}
	func applyPaths(_ call: (String) -> String) -> Routes {
		return .init(.init(routes: registry.routes.map { (call($0.key), $0.value) }))
	}
	func applyFuncs<NewOut>(_ call: @escaping (Future<RouteValueBox<OutType>>) -> Future<RouteValueBox<NewOut>>) -> Routes<InType, NewOut> {
		return .init(.init(routes: registry.routes.map {
			let (path, fnc) = $0
			return (path, { call(try fnc($0)) })
		}))
	}
	func apply<NewOut>(paths: (String) -> String, funcs call: @escaping (Future<RouteValueBox<OutType>>) -> Future<RouteValueBox<NewOut>>) -> Routes<InType, NewOut> {
		return .init(.init(routes: registry.routes.map {
			let (path, fnc) = $0
			return (paths(path), { call(try fnc($0)) })
		}))
	}
}

public func root() -> Routes<HTTPRequest, HTTPRequest> {
	return .init(.init(["/":{$0}]))
}

public func root<NewOut>(_ call: @escaping (HTTPRequest) throws -> NewOut) -> Routes<HTTPRequest, NewOut> {
	return .init(.init(["/":{$0.thenThrowing{RouteValueBox($0.state, try call($0.value))}}]))
}

public func root<NewOut>(path: String = "/", _ type: NewOut.Type) -> Routes<NewOut, NewOut> {
	return .init(.init([path:{$0}]))
}

public extension Routes {
	func then<NewOut>(_ call: @escaping (OutType) throws -> NewOut) -> Routes<InType, NewOut> {
		return applyFuncs {
			return $0.thenThrowing {
				return RouteValueBox($0.state, try call($0.value))
			}
		}
	}
	func then<NewOut>(_ call: @escaping () throws -> NewOut) -> Routes<InType, NewOut> {
		return applyFuncs {
			return $0.thenThrowing {
				return RouteValueBox($0.state, try call())
			}
		}
	}
}

public extension Routes {
	subscript(dynamicMember name: String) -> Routes {
		return path(name)
	}
	subscript<NewOut>(dynamicMember name: String) -> (@escaping (OutType) throws -> NewOut) -> Routes<InType, NewOut> {
		return {self.path(name, $0)}
	}
	subscript<NewOut>(dynamicMember name: String) -> (@escaping () throws -> NewOut) -> Routes<InType, NewOut> {
		return { call in self.path(name, { _ in return try call()})}
	}
}

public extension Routes {
	func path(_ name: String) -> Routes {
		return apply(
			paths: {$0.appending(component: name)},
			funcs: {
				$0.thenThrowing {
					$0.state.advanceComponent()
					return $0
				}
			}
		)
	}
	func path<NewOut>(_ name: String, _ call: @escaping (OutType) throws -> NewOut) -> Routes<InType, NewOut> {
		return apply(
			paths: {$0.appending(component: name)},
			funcs: {
				$0.thenThrowing {
					$0.state.advanceComponent()
					return RouteValueBox($0.state, try call($0.value))
				}
			}
		)
	}
	func path<NewOut>(_ name: String, _ call: @escaping () throws -> NewOut) -> Routes<InType, NewOut> {
		return apply(
			paths: {$0.appending(component: name)},
			funcs: {
				$0.thenThrowing {
					$0.state.advanceComponent()
					return RouteValueBox($0.state, try call())
				}
			}
		)
	}
}

public extension Routes {
	func ext(_ ext: String) -> Routes {
		let ext = ext.ext
		return applyPaths { $0 + ext }
	}
	func ext<NewOut>(_ ext: String,
					  contentType: String? = nil,
					  _ call: @escaping (OutType) throws -> NewOut) -> Routes<InType, NewOut> {
		let ext = ext.ext
		return apply(
			paths: {$0 + ext},
			funcs: {
				$0.thenThrowing {
					return RouteValueBox($0.state, try call($0.value))
				}
			}
		)
	}
}

public extension Routes {
	func wild<NewOut>(_ call: @escaping (OutType, String) throws -> NewOut) -> Routes<InType, NewOut> {
		return apply(
			paths: {$0.appending(component: "*")},
			funcs: {
				$0.thenThrowing {
					let c = $0.state.currentComponent ?? "-error-"
					$0.state.advanceComponent()
					return RouteValueBox($0.state, try call($0.value, c))
				}
			}
		)
	}
	func wild(name: String) -> Routes {
		return apply(
			paths: {$0.appending(component: "*")},
			funcs: {
				$0.thenThrowing {
					$0.state.request.uriVariables[name] = $0.state.currentComponent ?? "-error-"
					$0.state.advanceComponent()
					return $0
				}
			}
		)
	}
	func trailing<NewOut>(_ call: @escaping (OutType, String) throws -> NewOut) -> Routes<InType, NewOut> {
		return apply(
			paths: {$0.appending(component: "**")},
			funcs: {
				$0.thenThrowing {
					let c = $0.state.trailingComponents ?? "-error-"
					$0.state.advanceComponent()
					return RouteValueBox($0.state, try call($0.value, c))
				}
			}
		)
	}
}

public extension Routes {
	func request<NewOut>(_ call: @escaping (OutType, HTTPRequest) throws -> NewOut) -> Routes<InType, NewOut> {
		return applyFuncs {
			$0.thenThrowing {
				return RouteValueBox($0.state, try call($0.value, $0.state.request))
			}
		}
	}
	func readBody<NewOut>(_ call: @escaping (OutType, HTTPRequestContentType) throws -> NewOut) -> Routes<InType, NewOut> {
		return applyFuncs {
			$0.then {
				box in
				return box.state.request.readContent().thenThrowing {
					return RouteValueBox(box.state, try call(box.value, $0))
				}
			}
		}
	}
	func statusCheck(_ handler: @escaping (OutType) throws -> HTTPResponseStatus) -> Routes<InType, OutType> {
		return then {
			switch try handler($0).code {
			case 200..<300:
				return $0
			default:
				throw TerminationType.criteriaFailed
			}
		}
	}
	func decode<Type: Decodable, NewOut>(_ type: Type.Type,
										 _ handler: @escaping (OutType, Type) throws -> NewOut) -> Routes<InType, NewOut> {
		return readBody { a, _ in return a }.request {
			return try handler($0, try $1.decode(Type.self))
		}
	}
	func decode<Type: Decodable>(_ type: Type.Type) -> Routes<InType, Type> {
		return readBody { a, _ in return a }.request {
			return try $1.decode(Type.self)
		}
	}
}

public extension Routes {
	func dir<NewOut>(_ call: (Routes<OutType, OutType>) -> [Routes<OutType, NewOut>]) -> Routes<InType, NewOut> {
		return dir(call(root(OutType.self)))
	}
	func dir<NewOut>(_ registries: [Routes<OutType, NewOut>]) -> Routes<InType, NewOut> {
		let reg = RouteRegistry(routes: registries.flatMap { $0.registry.routes })
		return .init(registry.append(reg))
	}
	func dir<NewOut>(_ registry: Routes<OutType, NewOut>, _ registries: Routes<OutType, NewOut>...) -> Routes<InType, NewOut> {
		return dir([registry] + registries)
	}
}

public extension Routes where OutType: Encodable {
	func json() -> Routes<InType, HTTPOutput> {
		return then { try JSONOutput($0) }
	}
}

public extension Routes where OutType: CustomStringConvertible {
	func text() -> Routes<InType, HTTPOutput> {
		return then { TextOutput($0) }
	}
}
