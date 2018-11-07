import PerfectCRUD
import HTTPCRUDLib
import NIO

let big1024 = String(repeating: "A", count: 1024)
let big2048 = String(repeating: "A", count: 2048)
let big4096 = String(repeating: "A", count: 4096)
let big8192 = String(repeating: "A", count: 8192)

let prefix = "abc"

func printTupes(_ t: [(String, String)]) {
	for c in "abcdefghijklmnopqrstuvwxyz" {
		let key = prefix + String(c)
		let _ = t.first { $0.0 == key }.map { $0.1 }
		//				print(fnd)
	}
}

checkCRUDRoutes()

let dataRoutes = root().GET.dir{[
	$0.empty { "" },
	$0.path("1024") { big1024 },
	$0.path("2048") { big2048 },
	$0.path("4096") { big4096 },
	$0.path("8192") { big8192 },
]}

let argsRoutes: Routes<HTTPRequest, String> = root().dir{[
	$0.GET.getArgs2048 {
		printTupes($0.searchArgs)
		return big2048
	},
	$0.POST.dir{[
		$0.postArgs2048.readBody {
			if case .urlForm(let params) = $1 {
				printTupes(params)
			}
			return big2048
		},
		$0.postArgsMulti2048.readBody {
			if case .multiPartForm(let reader) = $1 {
				for c in "abcdefghijklmnopqrstuvwxyz" {
					let key = prefix + String(c)
					let _ = reader.bodySpecs.first { $0.fieldName == key }.map { $0.fieldValue }
					//					print(fnd)
				}
			}
			return big2048
		},
	]}
]}

let create = root().POST.create.decode(CRUDUser.self).db(try crudDB()) {
	(user: CRUDUser, db: Database<SQLite>) throws -> CRUDUser in
	try db.sql("BEGIN IMMEDIATE")
	try db.table(CRUDUser.self).insert(user)
	try db.sql("COMMIT")
	return user
}.json()
let update = root().POST.update.decode(CRUDUser.self).db(try crudDB()) {
	user, db throws -> CRUDUser in
	try db.sql("BEGIN IMMEDIATE")
	try db.table(CRUDUser.self).where(\CRUDUser.id == user.id).update(user)
	try db.sql("COMMIT")
	return user
}.json()
let delete = root().POST.delete.decode(CRUDUserRequest.self).db(try crudDB()) {
	req, db throws -> CRUDUserRequest in
	try db.sql("BEGIN IMMEDIATE")
	try db.table(CRUDUser.self).where(\CRUDUser.id == req.id).delete()
	try db.sql("COMMIT")
	return req
}.json()

let read = root().GET.read.wild {$1}.db(try crudDB()) {
	id, db throws -> CRUDUser in
	guard let user = try db.table(CRUDUser.self).where(\CRUDUser.id == id).first() else {
		throw HTTPOutputError(status: .notFound)
	}
	return user
}.json()

let crudUserRoutes: Routes<HTTPRequest, HTTPOutput> =
	root()
		.statusCheck { crudRoutesEnabled ? .ok : .internalServerError }
		.user
		.dir(
			create,
			read,
			update,
			delete)

let routes: Routes<HTTPRequest, HTTPOutput> = root()
//	.then { print($0.uri) ; return $0 }
	.dir(dataRoutes.text(),
		 argsRoutes.text(),
		 crudUserRoutes)

let count = System.coreCount
let servers = try (0..<count).map { _ in return try routes.bind(port: 9000).listen() }
print("Server listening on port 9000 with \(System.coreCount) cores")
try servers.forEach { try $0.wait() }
