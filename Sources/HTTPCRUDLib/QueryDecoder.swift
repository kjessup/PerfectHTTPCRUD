//
//  QueryDecoder.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-11-11.
//

import Foundation

private let ampChar = "&".utf8.first!
private let eqChar = "=".utf8.first!

private extension String {
	init?(_ slice: ArraySlice<UInt8>) {
		self.init(validatingUTF8: Array(slice))
	}
}

public struct QueryDecoder {
	typealias A = Array<UInt8>
	typealias I = A.Index
	typealias R = Range<I>
	struct RangeTriple {
		let start: I
		let middle: I
		let end: I
	}
	let collection: A
	var ranges: [RangeTriple] = []
	var lookup: [String:[Int]] = [:]
	public init(_ c: [UInt8]) {
		collection = c
		build()
	}
	
	func triple2Tuple(_ triple: RangeTriple) -> (String, ArraySlice<UInt8>) {
		let nameSlice: ArraySlice<UInt8>
		let valueSlice: ArraySlice<UInt8>
		if triple.middle == collection.endIndex {
			nameSlice = collection[triple.start...]
			valueSlice = ArraySlice<UInt8>(repeating: 0, count: 0)
		} else {
			nameSlice = collection[triple.start..<triple.middle-1]
			valueSlice = collection[triple.middle..<triple.end]
		}
		return (String(nameSlice) ?? "", valueSlice)
	}
	
	func triple2Value(_ triple: RangeTriple) -> ArraySlice<UInt8> {
		let valueSlice: ArraySlice<UInt8>
		if triple.middle == collection.endIndex {
			valueSlice = ArraySlice<UInt8>(repeating: 0, count: 0)
		} else {
			valueSlice = collection[triple.middle..<triple.end]
		}
		return valueSlice
	}
	
	public func map<T>(_ call: ((String,String)) throws -> T) rethrows -> [T] {
		return try mapBytes {
			return try call(($0.0, String($0.1) ?? ""))
		}
	}
	
	public func mapBytes<T>(_ call: ((String,ArraySlice<UInt8>)) throws -> T) rethrows -> [T] {
		return try ranges.map {try call(triple2Tuple($0))}
	}
	
	public func get(_ key: String) -> [ArraySlice<UInt8>] {
		guard let fnd = lookup[key] else {
			return []
		}
		return fnd.map { triple2Value(ranges[$0]) }
	}
	
	public subscript(_ key: String) -> [String] {
		return get(key).map { String($0) ?? "" }
	}
	
	mutating func build() {
		let end = collection.endIndex
		var s = collection.startIndex
		
		while s < end {
			let startI = s
			var c = collection[s]
			while c != ampChar && c != eqChar {
				s += 1
				guard s < end else {
					break
				}
				c = collection[s]
			}
			let middleI: I
			let endI: I
			switch c {
			case eqChar:
				s += 1
				middleI = s
				while s < end {
					c = collection[s]
					if c == ampChar {
						break
					}
					s += 1
				}
				endI = s
			case ampChar:
				fallthrough
			default:
				middleI = s
				endI = s
			}
			if c == ampChar {
				s += 1
			}
			ranges.append(RangeTriple(start: startI, middle: middleI, end: endI))
		}
		buildLookup()
	}
	mutating func buildLookup() {
		lookup = [:]
		for i in 0..<ranges.count {
			let triple = ranges[i]
			let nameSlice: ArraySlice<UInt8>
			if triple.middle == collection.endIndex {
				nameSlice = collection[triple.start...]
			} else if collection[triple.middle - 1] != eqChar {
				nameSlice = collection[triple.start..<triple.middle]
			} else {
				nameSlice = collection[triple.start..<triple.middle-1]
			}
			if let s = String(nameSlice) {
				if let fnd = lookup[s] {
					lookup[s] = fnd + [i]
				} else {
					lookup[s] = [i]
				}
			}
		}
	}
}
