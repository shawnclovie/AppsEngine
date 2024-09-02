//
//  constants.swift
//  
//
//  Created by Shawn Clovie on 15/8/2022.
//

import Foundation
import AppsEngine

extension Keys {
	public static let _id = "_id"
}

extension Errors {
	public static let databasePrimaryDataInvalid = WrapError(.database, "primary_data_invalid")
}
