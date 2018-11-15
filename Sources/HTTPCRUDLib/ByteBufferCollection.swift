//
//  ByteBufferCollection.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-11-13.
//

import NIO

struct ByteBufferCollection {
	let buffers: [ByteBuffer]
	let offset: Int // explicit offset into bytes
	init(buffers: [ByteBuffer] = [], offset: Int = 0) {
		self.buffers = buffers
		self.offset = offset
	}
	var count: Int {
		return buffers.reduce(0) { $0 + $1.readableBytes } - offset
	}
	subscript(_ index: Int) -> UInt8 {
		guard let (blockIndex, indexIndex) = bufferIndex(containing: index) else {
			return 0
		}
		return buffers[blockIndex].getInteger(at: indexIndex) ?? 0
	}
	func withRange<T>(_ range: PartialRangeFrom<Int>, _ call: (UnsafeMutableRawPointer) throws -> T) rethrows -> T? {
		return try withRange(range.lowerBound..<count, call)
	}
	func withRange<T>(_ range: Range<Int>, _ call: (UnsafeMutableRawPointer) throws -> T) rethrows -> T? {
		let start = range.startIndex
		guard let (blockIdx, index) = bufferIndex(containing: start) else {
			return nil
		}
		var block = buffers[blockIdx]
		let readable = block.readableBytes
		if readable - index >= range.count {
			return try block.withUnsafeMutableReadableBytes {
				p in
				return try call(p.baseAddress! + index)
			}
		}
		var accum = block.getBytes(at: index, length: readable - index) ?? []
		var remaining = readable - index
		var bIdx = blockIdx
		while remaining < 0 {
			bIdx += 1
			let nextBlock = buffers[bIdx]
			let thisRead = min(nextBlock.readableBytes, remaining)
			accum.append(contentsOf: nextBlock.getBytes(at: 0, length: thisRead) ?? [])
			remaining -= thisRead
		}
		return try call(&accum)
	}
	private func bufferIndex(containing index: Int) -> (block: Int, index: Int)? {
		let index = index + offset
		var cum = 0
		for i in 0..<buffers.count {
			let b = buffers[i]
			let readable = b.readableBytes
			if readable > index - cum {
				return (i, index - cum)
			}
			cum += readable
		}
		return nil
	}
	func append(collection: ByteBufferCollection) -> ByteBufferCollection {
		return .init(buffers: buffers + collection.buffers, offset: offset)
	}
	func trim(to index: Int) -> ByteBufferCollection {
		guard let (blockIndex, indexIndex) = bufferIndex(containing: index) else {
			return self
		}
		let blocks = Array(buffers[blockIndex...])
		return ByteBufferCollection(buffers: blocks, offset: indexIndex)
	}
}

