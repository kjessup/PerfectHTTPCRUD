import PerfectHTTP
import Foundation

public typealias ComponentGenerator = IndexingIterator<[String]>

extension String {
	var components: [String] {
		return self.split(separator: "/").map(String.init)
	}
	var componentGenerator: ComponentGenerator {
		return self.split(separator: "/").map(String.init).makeIterator()
	}
	// need url decoding component generator
	func appending(component name: String) -> String {
		if hasSuffix("/") {
			return self + name
		}
		return self + "/" + name.split(separator: "/").joined(separator: "/")
	}
	var cleanedComponents: String {
		return components.joined(separator: "/")
	}
	var componentBase: String? {
		return self.components.first
	}
	var componentName: String? {
		return self.components.last
	}
}

public enum TerminationType: Error {
	case error(Error)
	case criteriaFailed
	case internalError
}
