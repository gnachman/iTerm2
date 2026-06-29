//
//  iTermDatabase.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

struct iTermParameterizedSQLStatement {
    var sql: String
    var args: [Any]
    var isQuery = false
}

protocol iTermDatabaseResultSetInitializable {
    init?(dbResultSet: iTermDatabaseResultSet)
}

extension iTermDatabase {
    func executeUpdate(_ sql: String, withArguments args: [Any?]) throws {
        try executeUpdate(sql, withNonOptionalArguments: args.map {
            if let value = $0 {
                value
            } else {
                NSNull()
            }
        })
    }

    @discardableResult
    func executeQuery(_ sql: String, withArguments args: [Any?]) throws -> iTermDatabaseResultSet? {
        return try executeQuery(sql, withNonOptionalArguments: args.map {
            if let value = $0 {
                value
            } else {
                NSNull()
            }
        })
    }

    @discardableResult
    func executeStatements<T: iTermDatabaseResultSetInitializable>(_ statements: [iTermParameterizedSQLStatement]) throws -> [T]? {
        return try self.transaction {
            var result: Array<T>?
            for statement in statements {
                if statement.isQuery {
                    result = Array<T>()
                    let resultSet = try executeQuery(statement.sql, withNonOptionalArguments: statement.args)
                    while resultSet.next() {
                        if let entry = T(dbResultSet: resultSet) {
                            result?.append(entry)
                        }
                    }
                    resultSet.close()
                } else {
                    try executeUpdate(statement.sql, withNonOptionalArguments: statement.args)
                }
            }
            return result
        }
    }

    func transaction<T>(_ closure: () throws -> (T)) rethrows -> T {
        beginDeferredTransaction()
        DLog("Begin transaction");
        do {
            let value = try closure()
            commit()
            return value
        } catch {
            DLog("\(error)")
            rollback()
            throw error
        }
    }
}
