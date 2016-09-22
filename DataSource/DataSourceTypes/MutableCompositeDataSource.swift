//
//  MutableCompositeDataSource.swift
//  DataSource
//
//  Created by Vadim Yelagin on 15/06/15.
//  Copyright (c) 2015 Fueled. All rights reserved.
//

import Foundation
import ReactiveSwift
import Result

/// `DataSource` implementation that is composed of a mutable array
/// of other dataSources (called inner dataSources).
///
/// See `CompositeDataSource` for details.
///
/// The array of innerDataSources can be modified by calling methods that perform
/// individual changes and instantly make the dataSource emit
/// a corresponding dataChange.
public final class MutableCompositeDataSource: DataSource {

	public let changes: Signal<DataChange, NoError>
	fileprivate let observer: Observer<DataChange, NoError>
	fileprivate let disposable = CompositeDisposable()

	fileprivate let _innerDataSources: MutableProperty<[DataSource]>

	public var innerDataSources: Property<[DataSource]> {
		return Property(_innerDataSources)
	}

	public init(_ inner: [DataSource] = []) {
		(self.changes, self.observer) = Signal<DataChange, NoError>.pipe()
		self._innerDataSources = MutableProperty(inner)
		self.disposable += self._innerDataSources.producer
			.flatMap(.latest, transform: changesOfInnerDataSources)
			.start(self.observer)
	}

	deinit {
		self.observer.sendCompleted()
		self.disposable.dispose()
	}

	public var numberOfSections: Int {
		return self._innerDataSources.value.reduce(0) {
			subtotal, dataSource in
			return subtotal + dataSource.numberOfSections
		}
	}

	public func numberOfItemsInSection(_ section: Int) -> Int {
		let (index, innerSection) = mapInside(self._innerDataSources.value, section)
		return self._innerDataSources.value[index].numberOfItemsInSection(innerSection)
	}

	public func supplementaryItemOfKind(_ kind: String, inSection section: Int) -> Any? {
		let (index, innerSection) = mapInside(self._innerDataSources.value, section)
		return self._innerDataSources.value[index].supplementaryItemOfKind(kind, inSection: innerSection)
	}

	public func itemAtIndexPath(_ indexPath: IndexPath) -> Any {
		let (index, innerSection) = mapInside(self._innerDataSources.value, indexPath.section)
		let innerPath = indexPath.ds_setSection(innerSection)
		return self._innerDataSources.value[index].itemAtIndexPath(innerPath)
	}

	public func leafDataSourceAtIndexPath(_ indexPath: IndexPath) -> (DataSource, IndexPath) {
		let (index, innerSection) = mapInside(self._innerDataSources.value, indexPath.section)
		let innerPath = indexPath.ds_setSection(innerSection)
		return self._innerDataSources.value[index].leafDataSourceAtIndexPath(innerPath)
	}

	/// Inserts a given inner dataSource at a given index
	/// and emits `DataChangeInsertSections` for its sections.
	public func insertDataSource(_ dataSource: DataSource, atIndex index: Int) {
		let sections = self.sectionsOfDataSource(dataSource, atIndex: index)
		self._innerDataSources.value.insert(dataSource, at: index)
		if sections.count > 0 {
			let change = DataChangeInsertSections(sections: sections)
			self.observer.send(value: change)
		}
	}

	/// Deletes an inner dataSource at a given index
	/// and emits `DataChangeDeleteSections` for its sections.
	public func deleteDataSourceAtIndex(_ index: Int) {
		let sections = self.sectionsOfDataSourceAtIndex(index)
		self._innerDataSources.value.remove(at: index)
		if sections.count > 0 {
			let change = DataChangeDeleteSections(sections: sections)
			self.observer.send(value: change)
		}
	}

	/// Replaces an inner dataSource at a given index with another inner dataSource
	/// and emits a batch of `DataChangeDeleteSections` and `DataChangeInsertSections`
	/// for their sections.
	public func replaceDataSourceAtIndex(_ index: Int, withDataSource dataSource: DataSource) {
		var batch: [DataChange] = []
		let oldSections = self.sectionsOfDataSourceAtIndex(index)
		if oldSections.count > 0 {
			batch.append(DataChangeDeleteSections(sections: oldSections))
		}
		let newSections = self.sectionsOfDataSource(dataSource, atIndex: index)
		if newSections.count > 0 {
			batch.append(DataChangeInsertSections(sections: newSections))
		}
		self._innerDataSources.value[index] = dataSource
		if !batch.isEmpty {
			let change = DataChangeBatch(batch)
			self.observer.send(value: change)
		}
	}

	/// Moves an inner dataSource at a given index to another index
	/// and emits a batch of `DataChangeMoveSection` for its sections.
	public func moveDataSourceAtIndex(index oldIndex: Int, toIndex newIndex: Int) {
		let oldLocation = mapOutside(self._innerDataSources.value, oldIndex)(0)
		let dataSource = self._innerDataSources.value.remove(at: oldIndex)
		self._innerDataSources.value.insert(dataSource, at: newIndex)
		let newLocation = mapOutside(self._innerDataSources.value, newIndex)(0)
		let numberOfSections = dataSource.numberOfSections
		let batch: [DataChange] = (0 ..< numberOfSections).map {
			DataChangeMoveSection(from: oldLocation + $0, to: newLocation + $0)
		}
		if !batch.isEmpty {
			let change = DataChangeBatch(batch)
			self.observer.send(value: change)
		}
	}

	fileprivate func sectionsOfDataSource(_ dataSource: DataSource, atIndex index: Int) -> [Int] {
		let location = mapOutside(self._innerDataSources.value, index)(0)
		let length = dataSource.numberOfSections
		return Array(location ..< location + length)
	}

	fileprivate func sectionsOfDataSourceAtIndex(_ index: Int) -> [Int] {
		let dataSource = self._innerDataSources.value[index]
		return self.sectionsOfDataSource(dataSource, atIndex: index)
	}

}

private func changesOfInnerDataSources(_ innerDataSources: [DataSource]) -> SignalProducer<DataChange, NoError> {
	let arrayOfSignals = innerDataSources.enumerated().map {
		index, dataSource in
		return dataSource.changes.map {
			$0.mapSections(mapOutside(innerDataSources, index))
		}
	}
	return SignalProducer {
		observer, disposable in
		for signal in arrayOfSignals {
			disposable += signal.observe(observer)
		}
	}
}
