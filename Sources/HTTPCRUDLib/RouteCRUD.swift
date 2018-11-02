//
//  RouteCRUD.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-10-28.
//

import Foundation
import PerfectCRUD
import Dispatch

fileprivate let foreignEventsQueue = DispatchQueue(label: "foreignEventsQueue", attributes: .concurrent)

public struct ScopedComponents<ObjType, InType, OutType> {
	typealias R = Routes<InType, OutType>
}

public extension Routes {
	
}
