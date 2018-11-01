import HTTPCRUDLib
import PerfectCRUD
import NIO

CRUDLogging.queryLogDestinations = []

let big1024 = String(repeating: "A", count: 1024)
let big2048 = String(repeating: "A", count: 2048)
let big4096 = String(repeating: "A", count: 4096)
let big8192 = String(repeating: "A", count: 8192)

struct ID: Codable {
	let id: String
}

let prefix = "abc"

func printTupes(_ t: [(String, String)]) {
	for c in "abcdefghijklmnopqrstuvwxyz" {
		let key = prefix + String(c)
		let _ = t.first { $0.0 == key }.map { $0.1 }
		//				print(fnd)
	}
}

let routes = root().dir{[
	$0.GET.dir{[
		$0.empty { "" },
		$0.path("1024") { big1024 },
		$0.path("2048") { big2048 },
		$0.path("4096") { big4096 },
		$0.path("8192") { big8192 },
		$0.getArgs2048 {
			printTupes($0.searchArgs)
			return big2048
		}
	]},
	$0.POST.dir{[
		$0.postArgs2048.readBody {
			switch $1 {
			case .urlForm(let params):
				printTupes(params)
			default:
				()
			}
			return big2048
		},
		$0.postArgsMulti2048.readBody {
			switch $1 {
			case .multiPartForm(let reader):
				for c in "abcdefghijklmnopqrstuvwxyz" {
					let key = prefix + String(c)
					let _ = reader.bodySpecs.first { $0.fieldName == key }.map { $0.fieldValue }
//					print(fnd)
				}
			default:
				()
			}
			return big2048
		},
	]}
]}.text()

let servers = try (0...System.coreCount).map { _ in return try routes.bind(port: 9000).listen() }
print("Server listening on port 9000 with \(System.coreCount) cores")
try servers.forEach { try $0.wait() }
