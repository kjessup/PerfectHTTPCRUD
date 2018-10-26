//
//  RouteRegistry.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-10-23.
//

import PerfectHTTP

public enum RouteError: Error, CustomStringConvertible {
	case duplicatedRoutes([String])
	
	public var description: String {
		switch self {
		case .duplicatedRoutes(let r):
			return "Duplicated routes: \(r.joined(separator: ", "))"
		}
	}
}

@dynamicMemberLookup
public struct RouteRegistry<InType, OutType> {
	typealias ResolveFunc = (HandlerState, InType) throws -> OutType
	struct RouteItem {
		let path: String
		let resolve: ResolveFunc
	}
	let routes: [RouteItem]
	init(_ routes: [RouteItem]) {
		self.routes = routes
	}
	func then<NewOut>(_ call: @escaping (HandlerState, OutType) throws -> NewOut) -> RouteRegistry<InType, NewOut> {
		return .init(routes.map {
			item in
			.init(path: item.path, resolve: {
				(state: HandlerState, t: InType) throws -> NewOut in
				return try call(state, item.resolve(state, t))
			})
		})
	}
	func validate() throws {
		let paths = routes.map { $0.path }.sorted()
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

extension RouteRegistry: CustomStringConvertible {
	public var description: String {
		return routes.map { $0.path }.sorted().joined(separator: "\n")
	}
}

public extension RouteRegistry {
	func path(_ name: String) -> RouteRegistry {
		return .init(
			routes.map {
				item in
				return RouteItem(path: item.path.appending(component: name),
								 resolve: {
										state, i throws -> OutType in
										defer { state.advanceComponent() }
										return try item.resolve(state, i)
				})
			}
		)
	}
	func path<NewOut>(_ name: String, _ call: @escaping (OutType) throws -> NewOut) -> RouteRegistry<InType, NewOut> {
		typealias RetType = RouteRegistry<InType, NewOut>
		return .init(
			routes.map {
				item in
				return RetType.RouteItem(path: item.path.appending(component: name),
										 resolve: {
											state, i throws -> NewOut in
											defer { state.advanceComponent() }
											return try call(item.resolve(state, i))
				})
			}
		)
	}
	func wild<NewOut>(_ call: @escaping (OutType, String) throws -> NewOut) -> RouteRegistry<InType, NewOut> {
		typealias RetType = RouteRegistry<InType, NewOut>
		return .init(
			routes.map {
				item in
				return RetType.RouteItem(path: item.path.appending(component: "*"),
										 resolve: {
											state, i throws -> NewOut in
											let o = try item.resolve(state, i)
											let component = state.currentComponent ?? "-error-"
											state.advanceComponent()
											return try call(o, component)
				})
			}
		)
	}
	func trailing<NewOut>(_ call: @escaping (OutType, String) throws -> NewOut) -> RouteRegistry<InType, NewOut> {
		typealias RetType = RouteRegistry<InType, NewOut>
		return .init(
			routes.map {
				item in
				return RetType.RouteItem(path: item.path.appending(component: "**"),
										 resolve: {
											state, i throws -> NewOut in
											let o = try item.resolve(state, i)
											let component = state.currentComponent ?? "-error-"
											state.advanceComponent()
											return try call(o, component)
				})
			}
		)
	}
	subscript(dynamicMember name: String) -> RouteRegistry {
		return path(name)
	}
	subscript<NewOut>(dynamicMember name: String) -> (@escaping (OutType) throws -> NewOut) -> RouteRegistry<InType, NewOut> {
		typealias RegType = RouteRegistry<OutType, NewOut>
		return {self.path(name, $0)}
	}
}

public extension RouteRegistry {
	func append<NewOut>(_ registry: RouteRegistry<OutType, NewOut>) -> RouteRegistry<InType, NewOut> {
		return .init(routes.flatMap {
			item in
			return registry.routes.map {
				subItem in
				return .init(path: item.path.appending(component: subItem.path),
							 resolve: {
								state, t throws -> NewOut in
								return try subItem.resolve(state, item.resolve(state, t))
				})
			}
		})
	}
	func append<NewOut>(_ registries: [RouteRegistry<OutType, NewOut>]) -> RouteRegistry<InType, NewOut> {
		return .init(registries.flatMap { self.append($0).routes })
	}
	func combine(_ registry: RouteRegistry<InType, OutType>) -> RouteRegistry<InType, OutType> {
		return .init(routes + registry.routes)
	}
	func combine(_ registries: [RouteRegistry<InType, OutType>]) -> RouteRegistry<InType, OutType> {
		return .init(routes + registries.flatMap { $0.routes })
	}
	func then<NewOut>(_ call: @escaping (OutType) throws -> NewOut) -> RouteRegistry<InType, NewOut> {
		return then {try call($1)}
	}
	func request<NewOut>(_ call: @escaping (OutType, HTTPRequest) throws -> NewOut) -> RouteRegistry<InType, NewOut> {
		return then {try call($1, $0.request)}
	}
	func statusCheck(_ handler: @escaping (OutType) throws -> HTTPResponseStatus) -> RouteRegistry<InType, OutType> {
		return then {
			state, i in
			switch try handler(i).code {
			case 200..<300:
				return i
			default:
				throw TerminationType.criteriaFailed
			}
		}
	}
//	func decode<Type: Decodable, NewOut>(_ type: Type.Type, _ handler: @escaping (OutType, Type) throws -> NewOut) -> RouteRegistry<InType, NewOut> {
//		return then {
//			state, i in
//			return try handler(i, try state.request.decode(Type.self))
//		}
//	}
}

//func +<In, Out>(lhs: RouteRegistry<In, Out>, rhs: RouteRegistry<In, Out>) -> RouteRegistry<In, Out> {
//	return lhs.combine(rhs)
//}
//
//func +<In, Out>(lhs: RouteRegistry<In, Out>, rhs: [RouteRegistry<In, Out>]) -> RouteRegistry<In, Out> {
//	return rhs.reduce(lhs, +)
//}

public extension RouteRegistry where OutType: Encodable {
	func json() -> RouteRegistry<InType, HTTPOutput> {
		return then {
			state, i in
			return try JSONOutput(i)
		}
	}
}

public extension RouteRegistry where OutType: CustomStringConvertible {
	func text() -> RouteRegistry<InType, HTTPOutput> {
		return then {
			state, i in
			return TextOutput(i)
		}
	}
}

public func root() -> RouteRegistry<HTTPRequest, HTTPRequest> {
	return .init([
		.init(path: "/", resolve: {
			(_, t: HTTPRequest) throws -> HTTPRequest in
			return t
		})
	])
}

public func root<NewOut>(_ call: @escaping (HTTPRequest) throws -> NewOut) -> RouteRegistry<HTTPRequest, NewOut> {
	return .init([
		.init(path: "/", resolve: {
			(_, t: HTTPRequest) throws -> NewOut in
			return try call(t)
		})
	])
}
