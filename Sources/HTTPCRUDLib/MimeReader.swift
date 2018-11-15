//
//  MimeReader.swift
//  PerfectLib
//
//  Created by Kyle Jessup on 7/6/15.
//	Copyright (C) 2015 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

import Foundation
import NIO
#if os(Linux)
	import LinuxBridge
	let S_IRUSR = __S_IREAD
	let S_IRGRP	= (S_IRUSR >> 3)
	let S_IWGRP	= (SwiftGlibc.S_IWUSR >> 3)
	let S_IROTH = (S_IRGRP >> 3)
	let S_IWOTH = (S_IWGRP >> 3)
#else
	import Darwin
#endif
import PerfectLib

enum MimeReadState {
	case stateNone
	case stateBoundary // next thing to be read will be a boundry
	case stateHeader // read header lines until data starts
	case stateFieldValue // read a simple value; name has already been set
	case stateFile // read file data until boundry
	case stateDone
}

let kMultiPartForm = "multipart/form-data"
let kBoundary = "boundary"

let kContentDisposition = "Content-Disposition".utf8.makeIterator()
let kContentType = "Content-Type".utf8.makeIterator()

let kPerfectTempPrefix = "perfect_upload_"

let mime_cr: UInt8 = 13
let mime_lf: UInt8 = 10
let mime_dash: UInt8 = 45

/// This class is responsible for reading multi-part POST form data, including handling file uploads.
/// Data can be given for parsing in little bits at a time by calling the `addTobuffer` function.
/// Any file uploads which are encountered will be written to the temporary directory indicated when the `MimeReader` is created.
/// Temporary files will be deleted when this object is deinitialized.
public final class MimeReader {
	
	/// Array of BodySpecs representing each part that was parsed.
	public var bodySpecs = [BodySpec]()
	
	var (multi, gotFile) = (false, false)
	
	var buffer = ByteBufferCollection()
	
	let tempDirectory: String
	var state: MimeReadState = .stateNone
	
	/// The boundary identifier.
	public var boundary = "" {
		didSet {
			boundaryIt = boundary.utf8.makeIterator()
		}
	}
	var boundaryIt: String.UTF8View.Iterator = "".utf8.makeIterator()
	/// This class represents a single part of a multi-part POST submission
	public class BodySpec {
		/// The name of the form field.
		public var fieldName = ""
		/// The value for the form field.
		/// Having a fieldValue and a file are mutually exclusive.
		public var fieldValue = ""
		var fieldValueTempBytes: [UInt8]?
		/// The content-type for the form part.
		public var contentType = ""
		/// The client-side file name as submitted by the form.
		public var fileName = ""
		/// The size of the file which was submitted.
		public var fileSize = 0
		/// The name of the temporary file which stores the file upload on the server-side.
		public var tmpFileName = ""
		/// The File object for the local temporary file.
		public var file: File?
		
		init() {
			
		}
		
		/// Clean up the BodySpec, possibly closing and deleting any associated temporary file.
		public func cleanup() {
			if let f = file {
				if f.exists {
					f.delete()
				}
				file = nil
			}
		}
		
		deinit {
			cleanup()
		}
	}
	
	/// Initialize given a Content-type header line.
	/// - parameter contentType: The Content-type header line.
	/// - parameter tempDir: The path to the directory in which to store temporary files. Defaults to "/tmp/".
	public init(_ contentType: String, tempDir: String = "/tmp/") {
		tempDirectory = tempDir
		if contentType.hasPrefix(kMultiPartForm) {
			multi = true
			if let range = contentType.range(of: kBoundary) {
				let startIndex = contentType.index(range.lowerBound, offsetBy: kBoundary.count+1)
				let endIndex = contentType.endIndex
				let boundaryString = String(contentType[startIndex..<endIndex])
				boundary.append("--")
				boundary.append(boundaryString)
				state = .stateBoundary
			}
		}
	}
	
	func openTempFile(spec spc: BodySpec) {
		spc.file = TemporaryFile(withPrefix: tempDirectory + kPerfectTempPrefix)
		spc.tmpFileName = spc.file!.path
	}
	
	func isBoundaryStart(start: Int, end: Int) -> Bool {
		var gen = boundaryIt
		var pos = start
		var next = gen.next()
		while let char = next {
			if pos == end || char != buffer[pos] {
				return false
			}
			pos += 1
			next = gen.next()
		}
		return next == nil // got to the end is success
	}
	
	func isField(name: String.UTF8View.Iterator, start: Int, end: Int) -> Int {
		var check = start
		var gen = name
		while check != end {
			if buffer[check] == 58 { // :
				return check
			}
			let gened = gen.next()
			if gened == nil {
				break
			}
			if tolower(Int32(gened!)) != tolower(Int32(buffer[check])) {
				break
			}
			check = check.advanced(by: 1)
		}
		return end
	}
	
	func pullValue(name nam: String, from: String) -> String {
		var accum = ""
		let option = String.CompareOptions.caseInsensitive
		if let nameRange = from.range(of: nam + "=", options: option) {
			var start = nameRange.upperBound
			let end = from.endIndex
			if from[start] == "\"" {
				start = from.index(after: start)
			}
			while start < end {
				if from[start] == "\"" || from[start] == ";" {
					break;
				}
				accum.append(from[start])
				start = from.index(after: start)
			}
		}
		return accum
	}
	
	@discardableResult
	func internalAddToBuffer() -> MimeReadState {
		var clearBuffer = true
		var position = 0
		let end = buffer.count
		while position != end {
			switch state {
			case .stateDone, .stateNone:
				return .stateNone
			case .stateBoundary:
				if end - position < boundary.count + 2 {
					buffer = buffer.trim(to: position)
					clearBuffer = false
					position = end
				} else {
					position += boundary.count
					if buffer[position] == mime_dash && buffer[position + 1] == mime_dash {
						state = .stateDone
						position += 2
					} else {
						state = .stateHeader
						bodySpecs.append(BodySpec())
					}
					if state != .stateDone {
						position += 2 // line end
					} else {
						position = end
					}
				}
			case .stateHeader:
				var eolPos = position
				while end - eolPos > 1 {
					let b1 = buffer[eolPos]
					let b2 = buffer[eolPos + 1]
					if b1 == mime_cr && b2 == mime_lf {
						break
					}
					eolPos += 1
				}
				if end - eolPos <= 1 { // no eol
					buffer = buffer.trim(to: position)
					clearBuffer = false
					position = end
				} else {
					let spec = bodySpecs.last!
					if eolPos != position {
						let check = isField(name: kContentDisposition, start: position, end: end)
						if check != end { // yes, content-disposition
							let lineRange = (check + 2)..<eolPos
							let line = buffer.withRange(lineRange) {
								String(bytesNoCopy: $0, length: lineRange.count, encoding: .utf8, freeWhenDone: false) ?? ""
							}
							let name = pullValue(name: "name", from: line ?? "")
							let fileName = pullValue(name: "filename", from: line ?? "")
							spec.fieldName = name
							spec.fileName = fileName
						} else {
							let check = isField(name: kContentType, start: position, end: end)
							if check != end { // yes, content-type
								let lineRange = (check+2)..<eolPos
								let line = buffer.withRange(lineRange) {
									String(bytesNoCopy: $0, length: lineRange.count, encoding: .utf8, freeWhenDone: false) ?? ""
								}
								spec.contentType = line ?? ""
							}
						}
						position = eolPos + 2
					}
					if (eolPos == position || position != end) && (end-position) > 1 && buffer[position] == mime_cr && buffer[position+1] == mime_lf {
						position += 2
						if spec.fileName.count > 0 {
							openTempFile(spec: spec)
							state = .stateFile
						} else {
							state = .stateFieldValue
							spec.fieldValueTempBytes = []
						}
					}
				}
			case .stateFieldValue:
				let spec = bodySpecs.last!
				while position != end {
					if buffer[position] == mime_cr {
						if end - position == 1 {
							buffer = buffer.trim(to: position)
							clearBuffer = false
							position = end
							continue
						}
						if buffer[position + 1] == mime_lf {
							if isBoundaryStart(start: position + 2, end: end) {
								position += 2
								state = .stateBoundary
								var bytes = spec.fieldValueTempBytes ?? []
								let line = String(bytesNoCopy: &bytes, length: bytes.count, encoding: .utf8, freeWhenDone: false) ?? ""
								spec.fieldValue = line
								spec.fieldValueTempBytes = nil
								break
							} else if end - position - 2 < boundary.count {
								// we are at the eol, but check to see if the next line may be starting a boundary
								if end - position < 4 || (buffer[position + 2] == mime_dash && buffer[position + 3] == mime_dash) {
									buffer = buffer.trim(to: position)
									clearBuffer = false
									position = end
									continue
								}
							}
							
						}
					}
					spec.fieldValueTempBytes!.append(buffer[position])
					position += 1
				}
			case .stateFile:
				let spec = bodySpecs.last!
				while position != end {
					if buffer[position] == mime_cr {
						if end - position == 1 {
							buffer = buffer.trim(to: position)
							clearBuffer = false
							position = end
							continue
						}
						if buffer[position + 1] == mime_lf {
							if isBoundaryStart(start: position + 2, end: end) {
								position += 2
								state = .stateBoundary
								// end of file data
								spec.file!.close()
								chmod(spec.file!.path, mode_t(S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH|S_IWOTH))
								break
							} else if end - position - 2 < boundary.count {
								// we are at the eol, but check to see if the next line may be starting a boundary
								if end - position < 4 || (buffer[position + 2] == mime_dash && buffer[position + 3] == mime_dash) {
									buffer = buffer.trim(to: position)
									clearBuffer = false
									position = end
									continue
								}
							}
						}
					}
					// write as much data as we reasonably can
					struct e: Error{}
					do {
						var writeEnd = 0
						let end = end - position
						try buffer.withRange(position...) {
							raw in
							let qPtr = raw.assumingMemoryBound(to: UInt8.self)
							while writeEnd < end {
								if qPtr[writeEnd] == mime_cr {
									if end - writeEnd < 2 {
										break
									}
									if qPtr[writeEnd + 1] == mime_lf {
										if isBoundaryStart(start: writeEnd + 2, end: end) {
											break
										} else if end - writeEnd - 2 < boundary.count {
											// we are at the eol, but check to see if the next line may be starting a boundary
											if end - writeEnd < 4 || (qPtr[writeEnd + 2] == mime_dash && qPtr[writeEnd + 3] == mime_dash) {
												break
											}
										}
									}
								}
								writeEnd += 1
							}
							let length = writeEnd - position
							let wrote = write(Int32(spec.file!.fd), raw, length)
							guard wrote == length else {
								throw e()
							}
							spec.fileSize += wrote
						}
						if (writeEnd == end) {
							buffer = .init()
						}
						position += writeEnd
						gotFile = true
					} catch let e {
						Log.error(message: "Exception while writing file upload data: \(e)")
						state = .stateNone
						break
					}
				}
			}
		}
		if clearBuffer {
			buffer = .init()
		}
		return state
	}
	
	/// Add data to be parsed.
	/// - parameter bytes: The array of UInt8 to be parsed.
	public func addToBuffer(bytes: [ByteBuffer]) {
		buffer = buffer.append(collection: ByteBufferCollection(buffers: bytes))
		if isMultiPart {
			internalAddToBuffer()
		}
	}
	
	/// Add data to be parsed.
	/// - parameter bytes: The array of UInt8 to be parsed.
//	public func addToBuffer(bytes byts: UnsafePointer<UInt8>, length: Int) {
//		if isMultiPart {
//			if self.buffer.count != 0 {
//				for i in 0..<length {
//					self.buffer.append(byts[i])
//				}
//				internalAddToBuffer(bytes: self.buffer)
//			} else {
//				var a = [UInt8]()
//				for i in 0..<length {
//					a.append(byts[i])
//				}
//				internalAddToBuffer(bytes: a)
//			}
//		} else {
//			for i in 0..<length {
//				self.buffer.append(byts[i])
//			}
//		}
//	}
	
	/// Returns true of the content type indicated a multi-part form.
	public var isMultiPart: Bool {
		return multi
	}
}
