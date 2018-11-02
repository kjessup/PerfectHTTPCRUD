//
//  CRUDRoutes.swift
//  PerfectHTTPCRUDExe
//
//  Created by Kyle Jessup on 2018-11-01.
//

import PerfectCRUD
import PerfectPostgreSQL

// This is only here for CENGN testing
// main HTTPCRUDLib will be moved to real repo

var crudRoutesEnabled = false

let dbHost = "localhost"
let dbName = "postgresdb"
let dbUser = "postgresuser"
let dbPassword = "postgresuser"

func crudTable<T: Codable>(_ t: T.Type) throws -> Table<T, Database<PostgresDatabaseConfiguration>> {
	return try crudDB().table(t)
}
func crudDB() throws -> Database<PostgresDatabaseConfiguration> {
	return Database(configuration:
		try PostgresDatabaseConfiguration(database: dbName,
										  host: dbHost,
										  username: dbUser,
										  password: dbPassword))
}

struct CRUDUser: Codable {
	let id: String
	let firstName: String
	let lastName: String
}

struct CRUDUserRequest: Codable {
	let id: String
}

func checkCRUDRoutes() {
	CRUDLogging.queryLogDestinations = []
	do {
		try crudDB().create(CRUDUser.self, primaryKey: \.id).index(\.firstName, \.lastName)
		crudRoutesEnabled = true
		print("CRUD routes enabled.")
	} catch {
		crudRoutesEnabled = false
		print("No database connection. CRUD routes disabled.")
	}
}
