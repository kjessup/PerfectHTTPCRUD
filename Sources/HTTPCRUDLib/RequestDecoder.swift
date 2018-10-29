//
//  RequestDecoder.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-10-28.
//

import Foundation
import NIOHTTP1

/// Extensions on HTTPRequest which permit the request body to be decoded to a Codable type.
public extension HTTPRequest {
	/// Decode the request body into the desired type, or throw an error.
	func decode<A: Decodable>(_ type: A.Type) throws -> A {
		if let contentType = headers.first(where: { $0.name == "content-type" })?.value,
				contentType.hasPrefix("application/json") {
//			guard let body = postBodyBytes else {
//				throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "This request requires JSON input."))
//			}
			let body = [UInt8]()//fix
			
			// this is not exactly ideal
			// fudging url vars and json post body is inefficient
			let data: Data
			if !uriVariables.isEmpty,
				var dict = try JSONSerialization.jsonObject(with: Data(bytes: body), options: []) as? [String:Any] {
				uriVariables.forEach {
					let (key, value) = $0
					dict[key] = value
				}
				data = try JSONSerialization.data(withJSONObject: dict, options: [])
			} else {
				data = Data(bytes: body)
			}
			do {
				return try JSONDecoder().decode(A.self, from: data)
			} catch let error as DecodingError
				where error.localizedDescription == "The data couldn’t be read because it is missing." {
					throw TerminationType.error(HTTPOutputError(status: .badRequest, description: "Error while decoding request object. This is usually caused by API misuse. Check your request input names."))
			}
		} else {
			return try A.init(from: RequestDecoder(request: self))
		}
	}
}

private enum SpecialType {
	case uint8Array, int8Array, data, uuid, date
	init?(_ type: Any.Type) {
		switch type {
		case is [Int8].Type:
			self = .int8Array
		case is [UInt8].Type:
			self = .uint8Array
		case is Data.Type:
			self = .data
		case is UUID.Type:
			self = .uuid
		case is Date.Type:
			self = .date
		default:
			return nil
		}
	}
}

class RequestReader<K : CodingKey>: KeyedDecodingContainerProtocol {
	typealias Key = K
	var codingPath: [CodingKey] = []
	var allKeys: [Key] = []
	let parent: RequestDecoder
	let params: [(String, String)]
//	let uploads: [MimeReader.BodySpec]?
	var request: HTTPRequest { return parent.request }
	init(_ p: RequestDecoder) {
		parent = p
		params = p.request.searchArgs
//		uploads = p.request.postFileUploads
	}
	func getValue<T: LosslessStringConvertible>(_ key: Key) throws -> T {
		let str: String
		let keyStr = key.stringValue
		if let v = request.uriVariables[keyStr] {
			str = v
//		} else if let files = uploads, let found = files.first(where: {$0.fieldName == keyStr}) {
//			str = found.fieldValue
		} else if let v = params.first(where: {$0.0 == keyStr}) {
			str = v.1
		} else {
			throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Key \(keyStr) not found."))
		}
		guard let ret = T.init(str) else {
			throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Could not convert to \(T.self).")
		}
		return ret
	}
	func contains(_ key: Key) -> Bool {
		if let _: String = try? getValue(key) {
			return true
		}
		return false
	}
	func decodeNil(forKey key: Key) throws -> Bool {
		return !contains(key)
	}
	func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
		return try getValue(key)
	}
	func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
		return try getValue(key)
	}
	func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
		return try getValue(key)
	}
	func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
		return try getValue(key)
	}
	func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
		return try getValue(key)
	}
	func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
		return try getValue(key)
	}
	func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
		return try getValue(key)
	}
	func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
		return try getValue(key)
	}
	func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
		return try getValue(key)
	}
	func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
		return try getValue(key)
	}
	func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
		return try getValue(key)
	}
	func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
		return try getValue(key)
	}
	func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
		return try getValue(key)
	}
	func decode(_ type: String.Type, forKey key: Key) throws -> String {
		return try getValue(key)
	}
	func decode<T>(_ t: T.Type, forKey key: Key) throws -> T where T : Decodable {
		if let special = SpecialType(t) {
			switch special {
			case .uint8Array, .int8Array, .data:
				throw DecodingError.keyNotFound(key, .init(codingPath: codingPath,
														   debugDescription: "The data type \(t) is not supported for GET requests."))
			case .uuid:
				let str: String = try getValue(key)
				guard let uuid = UUID(uuidString: str) else {
					throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Could not convert to \(t).")
				}
				return uuid as! T
			case .date:
				// !FIX! need to support better formats
				let str: String = try getValue(key)
				guard let date = Date(fromISO8601: str) else {
					throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Could not convert to \(t).")
				}
				return date as! T
			}
		}
		throw DecodingError.keyNotFound(key, .init(codingPath: codingPath,
												   debugDescription: "The data type \(t) is not supported for GET requests."))
	}
	func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
		fatalError("Unimplimented")
	}
	func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
		fatalError("Unimplimented")
	}
	func superDecoder() throws -> Decoder {
		fatalError("Unimplimented")
	}
	func superDecoder(forKey key: Key) throws -> Decoder {
		fatalError("Unimplimented")
	}
}

class RequestUnkeyedReader: UnkeyedDecodingContainer, SingleValueDecodingContainer {
	let codingPath: [CodingKey] = []
	var count: Int? = 1
	var isAtEnd: Bool { return currentIndex != 0 }
	var currentIndex: Int = 0
	let parent: RequestDecoder
	var decodedType: Any.Type?
	var typeDecoder: RequestDecoder?
	init(parent p: RequestDecoder) {
		parent = p
	}
	func advance(_ t: Any.Type) {
		currentIndex += 1
		decodedType = t
	}
	func decodeNil() -> Bool {
		return false
	}
	func decode(_ type: Bool.Type) throws -> Bool {
		advance(type)
		return false
	}
	func decode(_ type: Int.Type) throws -> Int {
		advance(type)
		return 0
	}
	func decode(_ type: Int8.Type) throws -> Int8 {
		advance(type)
		return 0
	}
	func decode(_ type: Int16.Type) throws -> Int16 {
		advance(type)
		return 0
	}
	func decode(_ type: Int32.Type) throws -> Int32 {
		advance(type)
		return 0
	}
	func decode(_ type: Int64.Type) throws -> Int64 {
		advance(type)
		return 0
	}
	func decode(_ type: UInt.Type) throws -> UInt {
		advance(type)
		return 0
	}
	func decode(_ type: UInt8.Type) throws -> UInt8 {
		advance(type)
		return 0
	}
	func decode(_ type: UInt16.Type) throws -> UInt16 {
		advance(type)
		return 0
	}
	func decode(_ type: UInt32.Type) throws -> UInt32 {
		advance(type)
		return 0
	}
	func decode(_ type: UInt64.Type) throws -> UInt64 {
		advance(type)
		return 0
	}
	func decode(_ type: Float.Type) throws -> Float {
		advance(type)
		return 0
	}
	func decode(_ type: Double.Type) throws -> Double {
		advance(type)
		return 0
	}
	func decode(_ type: String.Type) throws -> String {
		advance(type)
		return ""
	}
	func decode<T: Decodable>(_ type: T.Type) throws -> T {
		advance(type)
		return try T(from: parent)
	}
	func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
		fatalError("Unimplimented")
	}
	func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
		fatalError("Unimplimented")
	}
	func superDecoder() throws -> Decoder {
		currentIndex += 1
		return parent
	}
}

class RequestDecoder: Decoder {
	var codingPath: [CodingKey] = []
	var userInfo: [CodingUserInfoKey : Any] = [:]
	let request: HTTPRequest
	init(request r: HTTPRequest) {
		request = r
	}
	func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
		return KeyedDecodingContainer<Key>(RequestReader<Key>(self))
	}
	func unkeyedContainer() throws -> UnkeyedDecodingContainer {
		return RequestUnkeyedReader(parent: self)
	}
	func singleValueContainer() throws -> SingleValueDecodingContainer {
		return RequestUnkeyedReader(parent: self)
	}
}

