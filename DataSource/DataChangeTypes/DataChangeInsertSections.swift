//
//  DataChangeInsertSections.swift
//  DataSource
//
//  Created by Vadim Yelagin on 09/06/15.
//  Copyright (c) 2015 Fueled. All rights reserved.
//

import Foundation

public struct DataChangeInsertSections: DataChange {

	public let sections: [Int]

	public init(sections: [Int]) {
		self.sections = sections
	}

	public func apply(_ target: DataChangeTarget) {
		target.ds_insertSections(sections)
	}

	public func mapSections(_ transform: @escaping (Int) -> Int) -> DataChangeInsertSections {
		return DataChangeInsertSections(sections: sections.map(transform))
	}

}
