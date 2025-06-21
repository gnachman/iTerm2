//
//  iTermDatabase.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

extension iTermDatabase {
    @discardableResult
    func executeUpdate(_ sql: String, withArguments args: [Any]) -> Bool {
        return executeUpdate(sql, withNonOptionalArguments: args)
    }

    @discardableResult
    func executeUpdate(_ sql: String, withArguments args: [Any?]) -> Bool {
        return executeUpdate(sql, withNonOptionalArguments: args.map {
            if let value = $0 {
                value
            } else {
                NSNull()
            }
        })
    }

    @discardableResult
    func executeQuery(_ sql: String, withArguments args: [Any]) -> iTermDatabaseResultSet? {
        return executeQuery(sql, withNonOptionalArguments: args)
    }

    @discardableResult
    func executeQuery(_ sql: String, withArguments args: [Any?]) -> iTermDatabaseResultSet? {
        return executeQuery(sql, withNonOptionalArguments: args.map {
            if let value = $0 {
                value
            } else {
                NSNull()
            }
        })
    }
}
