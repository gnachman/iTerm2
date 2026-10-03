//
//  AsyncCommandRecipeRetryTests.swift
//  ModernTests
//
//  When a password manager command fails because its session was rejected, recovery replaces
//  the token and the command is retried. The token is baked into the command (its stdin for
//  adapters, its environment for 1Password), so the retry must build the command again. It
//  used to rerun the original, which failed the same way until the retries ran out, so a
//  Bitwarden user saw “Not authenticated.” and was never asked to log in again.
//

import XCTest
@testable import iTerm2SharedARC

final class AsyncCommandRecipeRetryTests: XCTestCase {
    private struct Rejected: Error {}

    // Returns output whose stdout is the token it was built with.
    private struct FakeCommand: CommandLinePasswordDataSourceExecutableCommand {
        let token: String

        func exec() throws -> Output {
            return output()
        }

        func execAsync(_ completion: @escaping (Output?, Error?) -> ()) {
            completion(output(), nil)
        }

        private func output() -> Output {
            var builder = CommandLinePasswordDataSource.OutputBuilder()
            builder.stdout = Data(token.utf8)
            builder.returnCode = 0
            builder.terminationReason = .exit
            return builder.tryBuild()!
        }
    }

    private func run(_ recipe: CommandLinePasswordDataSource.AsyncCommandRecipe<Void, String>) -> (String?, Error?) {
        let done = expectation(description: "recipe finished")
        var result: (String?, Error?) = (nil, nil)
        recipe.transformAsync(context: RecipeExecutionContext(window: nil), inputs: ()) { outputs, error in
            result = (outputs, error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    func testRetryRebuildsCommandWithRecoveredToken() {
        var token = "stale"
        var builds = 0
        let recipe = CommandLinePasswordDataSource.AsyncCommandRecipe<Void, String>(
            inputTransformer: { _, _, completion in
                builds += 1
                completion(.success(FakeCommand(token: token)))
            },
            recovery: { _, completion in
                token = "fresh"
                completion(nil)
            },
            outputTransformer: { output, completion in
                let seen = String(data: output.stdout, encoding: .utf8)!
                if seen == "stale" {
                    completion(.failure(Rejected()))
                } else {
                    completion(.success(seen))
                }
            })

        let (outputs, error) = run(recipe)
        XCTAssertNil(error)
        XCTAssertEqual(outputs, "fresh", "The retry must use the token recovery produced")
        XCTAssertEqual(builds, 2, "The command is built again for the retry")
    }

    func testGivesUpAfterRetriesWithLastError() {
        var builds = 0
        let recipe = CommandLinePasswordDataSource.AsyncCommandRecipe<Void, String>(
            inputTransformer: { _, _, completion in
                builds += 1
                completion(.success(FakeCommand(token: "stale")))
            },
            recovery: { _, completion in
                completion(nil)
            },
            outputTransformer: { _, completion in
                completion(.failure(Rejected()))
            })

        let (outputs, error) = run(recipe)
        XCTAssertNil(outputs)
        XCTAssertTrue(error is Rejected)
        XCTAssertEqual(builds, 4, "One attempt plus three retries")
    }

    func testRecoveryFailureStopsRetrying() {
        struct LoginCanceled: Error {}
        var builds = 0
        let recipe = CommandLinePasswordDataSource.AsyncCommandRecipe<Void, String>(
            inputTransformer: { _, _, completion in
                builds += 1
                completion(.success(FakeCommand(token: "stale")))
            },
            recovery: { _, completion in
                completion(LoginCanceled())
            },
            outputTransformer: { _, completion in
                completion(.failure(Rejected()))
            })

        let (_, error) = run(recipe)
        XCTAssertTrue(error is LoginCanceled)
        XCTAssertEqual(builds, 1)
    }
}
