//
//  ObjCExceptions.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/25/22.
//

import Foundation

func ObjCTry<T>(_ closure: () throws -> T) throws -> T {
    var result: Result<T, Error>? = nil
    let error = ObjCTryImpl {
        do {
            result = .success(try closure())
        } catch {
            result = .failure(error)
        }
    }
    switch result {
    case .success(let value):
        return value
    case .failure(let error):
        throw error
    case .none:
        throw error!
    }
}
