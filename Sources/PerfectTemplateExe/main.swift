import HTTPCRUDLib

let routes = root().append([
	root().hello { _ in return "Hello!" }.text()
])

let server = try routes.bind(port: 9000).listen()
try server.wait()
