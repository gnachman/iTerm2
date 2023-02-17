//
//  OnePasswordDataSource.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import Foundation

class OnePasswordDataSource: CommandLinePasswordDataSource {
    enum OPError: Error {
        case runtime
        case needsAuthentication
        case badOutput
        case canceledByUser
        case unexpectedError
        case unusableCLI
        case timeout
    }

    struct ListItemsEntry: Codable {
        let id: String
        let title: String
        let tags: [String]?
        let trashed: String
        let ainfo: String?
    }

    private var auth: OnePasswordTokenRequester.Auth? = nil

    // This is a short-lived cache used to consolidate availability checks in a series of related
    // operations.
    enum Availability {
        case uncached
        case wantCache
        case cached(Bool)
    }
    private var available = Availability.uncached

    private var requester: OnePasswordTokenRequester?
    private func asyncGetToken(_ completion: @escaping (Result<OnePasswordTokenRequester.Auth, Error>) -> ()) {
        switch auth {
        case .biometric, .token(_):
            completion(.success(auth!))
            return
        case .none:
            break
        }
        if requester != nil {
            DLog("WARNING: Overwriting existing token requester.")
        }
        requester = OnePasswordTokenRequester()
        requester?.asyncGet { [weak self] result in
            guard let self = self else {
                return
            }
            self.requester = nil
            switch result {
            case .failure(OPError.needsAuthentication):
                self.asyncGetToken(completion)
            case .success, .failure:
                completion(result)
            }
        }
    }

    private struct OnePasswordBasicCommandRecipe<Inputs, Outputs>: Recipe {
        private let dynamicRecipe: OnePasswordDynamicCommandRecipe<Inputs, Outputs>
        init(_ args: [String],
             dataSource: OnePasswordDataSource,
             outputTransformer: @escaping (Output) throws -> Outputs) {
            dynamicRecipe =
            OnePasswordDynamicCommandRecipe<Inputs, Outputs>(
                dataSource: dataSource,
                inputTransformer: { _, token in
                    var request = InteractiveCommandRequest(
                        command: OnePasswordUtils.pathToCLI,
                        args: args,
                        env: OnePasswordUtils.standardEnvironment(token: token))
                    request.deadline = Date(timeIntervalSinceNow: 10)
                    return request
                },
                outputTransformer: outputTransformer)
        }

        func transformAsync(inputs: Inputs,
                            completion: @escaping (Outputs?, Error?) -> ()) {
            dynamicRecipe.transformAsync(inputs: inputs, completion: completion)
        }
    }

    private struct OnePasswordDynamicCommandRecipe<Inputs, Outputs>: Recipe {
        private let commandRecipe: AsyncCommandRecipe<Inputs, Outputs>

        init(dataSource: OnePasswordDataSource,
             inputTransformer: @escaping (Inputs, OnePasswordTokenRequester.Auth) throws -> (CommandLinePasswordDataSourceExecutableCommand),
             outputTransformer: @escaping (Output) throws -> Outputs) {

            commandRecipe = AsyncCommandRecipe<Inputs, Outputs> { (inputs, completion) in
                dataSource.asyncGetToken { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let token):
                        do {
                            let transformedInput = try inputTransformer(inputs, token)
                            completion(.success(transformedInput))
                            return
                        } catch {
                            completion(.failure(error))
                        }
                    }
                }
            } recovery: { error, completion in
                if error as? OPError == OPError.needsAuthentication {
                    dataSource.auth = nil
                    dataSource.asyncGetToken { result in
                        switch result {
                        case .success:
                            completion(nil)
                        case .failure(let error):
                            completion(error)
                        }
                    }
                } else {
                    completion(error)
                }
            } outputTransformer: { output, completion in
                if output.timedOut {
                    let alert = NSAlert()
                    alert.messageText = "Timeout"
                    alert.informativeText = "1Password took too long to respond."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    completion(.failure(OPError.timeout))
                    return
                }
                if output.returnCode != 0 {
                    if output.stderr.smellsLike1PasswordAuthenticationError {
                        completion(.failure(OPError.needsAuthentication))
                    } else {
                        completion(.failure(OPError.runtime))
                    }
                    return
                }
                do {
                    let transformedOutput = try outputTransformer(output)
                    completion(.success(transformedOutput))
                    return
                } catch {
                    completion(.failure(error))
                    return
                }
            }
        }

        func transformAsync(inputs: Inputs,
                            completion: @escaping (Outputs?, Error?) -> ()) {
            commandRecipe.transformAsync(inputs: inputs, completion: completion)
        }
    }

    private var listAccountsCache: CachingVoidRecipe<[Account]>? = nil

    private var listAccountsRecipe: AnyRecipe<Void, [Account]> {
        if let listAccountsCache = listAccountsCache {
            return AnyRecipe<Void, [Account]>(listAccountsCache)
        }
        // This is equivalent to running this command and then parsing out the relevant fields from
        // the output:
        //     op item list --tags iTerm2 --format json | op item get --format=json -

        let args = ["item", "list", "--format=json", "--no-color", "--tags", "iTerm2"]
        let accountsRecipe = OnePasswordBasicCommandRecipe<Void, Data>(args, dataSource: self) { $0.stdout }

        let itemsRecipe = OnePasswordDynamicCommandRecipe<Data, [Account]>(
            dataSource: self) { data, token throws -> CommandLinePasswordDataSourceExecutableCommand in
                return CommandRequestWithInput(
                    command: OnePasswordUtils.pathToCLI,
                    args: ["item", "get", "--format=json", "--no-color", "-"],
                    env: OnePasswordUtils.standardEnvironment(token: token),
                    input: data)
            } outputTransformer: { output throws -> [Account] in
                if output.returnCode != 0 {
                    throw OPError.runtime
                }
                struct Field: Codable {
                    var id: String
                    var value: String?
                }
                struct Item: Codable {
                    var id: String
                    var title: String
                    var fields: [Field]
                }
                guard let phonyJson = String(data: output.stdout, encoding: .utf8) else {
                    throw OPError.runtime
                }
                let json = "[" + phonyJson.replacingOccurrences(of: "}\n{", with: "},\n{") + "]"
                let items = try JSONDecoder().decode([Item].self, from: json.data(using: .utf8)!)
                return items.map {
                    let username: String?
                    if let field = $0.fields.first(where: { field in
                        field.id == "username"
                    }) {
                        username = field.value
                    } else {
                        username = nil
                    }
                    return Account(identifier: CommandLinePasswordDataSource.AccountIdentifier(value: $0.id),
                                   userName: username ?? "",
                                   accountName: $0.title)
                }
            }

        let pipeline: AnyRecipe<Void, [Account]> = AnyRecipe(PipelineRecipe(accountsRecipe, itemsRecipe))
        let cache: CachingVoidRecipe<[Account]> = CachingVoidRecipe(pipeline, maxAge: 30 * 60)
        listAccountsCache = cache
        return AnyRecipe<Void, [Account]>(cache)
    }

    private var getPasswordRecipe: AnyRecipe<AccountIdentifier, Password> {
        return AnyRecipe(OnePasswordDynamicCommandRecipe<AccountIdentifier, Password>(dataSource: self) { accountIdentifier, token in
            return InteractiveCommandRequest(
                command: OnePasswordUtils.pathToCLI,
                args: ["item", "get", "--format=json", "--no-color", accountIdentifier.value],
                env: OnePasswordUtils.standardEnvironment(token: token))
        } outputTransformer: { output throws in
            if output.returnCode != 0 {
                throw OPError.runtime
            }
            struct Field: Codable {
                var id: String
                var type: String?
                var value: String?
                var totp: String?
            }
            struct Item: Codable {
                var id: String
                var title: String
                var fields: [Field]
            }
            guard let json = String(data: output.stdout, encoding: .utf8) else {
                throw OPError.runtime
            }
            let item = try JSONDecoder().decode(Item.self, from: json.data(using: .utf8)!)

            let password = try {
                let passwordField = item.fields.first { field in
                    field.id == "password"
                }
                guard let password = passwordField?.value else {
                    throw OPError.runtime
                }
                if password.hasSuffix("\r") {
                    return String(password.dropLast())
                }
                return password
            }()
            let otp = {
                let otpField = item.fields.first { field in
                    field.type == "OTP"
                }
                return otpField?.totp
            }()
            return Password(password: password, otp: otp)
        })
    }

    private var setPasswordRecipe: AnyRecipe<SetPasswordRequest, Void> {
        return AnyRecipe(UnsupportedRecipe<SetPasswordRequest, Void>(reason: "1Password's CLI has no secure way to change a password."))
    }

    private var deleteRecipe: AnyRecipe<AccountIdentifier, Void> {
        return AnyRecipe(OnePasswordDynamicCommandRecipe(dataSource: self) { accountID, token in
            return InteractiveCommandRequest(
                command: OnePasswordUtils.pathToCLI,
                args: ["item", "delete", accountID.value],
                env: OnePasswordUtils.standardEnvironment(token: token))
        } outputTransformer: { output in })
    }

    private var addAccountRecipe: AnyRecipe<AddRequest, AccountIdentifier> {
        return AnyRecipe(OnePasswordDynamicCommandRecipe(dataSource: self) { addRequest, token in
            let args = ["item",
                        "create",
                        "--category=login",
                        "--title=\(addRequest.accountName)",
                        "--tags=iTerm2",
                        "--generate-password",
                        "--format=json",
                        "username=\(addRequest.userName)"]
            var request = InteractiveCommandRequest(
                command: OnePasswordUtils.pathToCLI,
                args: args,
                env: OnePasswordUtils.standardEnvironment(token: token))
            request.useTTY = true
            return request
        } outputTransformer: { output in
            struct Response: Codable {
                var id: String
            }
            let response = try JSONDecoder().decode(Response.self, from: output.stdout)
            return AccountIdentifier(value: response.id)
        })
    }

    var configuration: Configuration {
        lazy var value = {
            Configuration(listAccountsRecipe: listAccountsRecipe,
                          getPasswordRecipe: getPasswordRecipe,
                          setPasswordRecipe: setPasswordRecipe,
                          deleteRecipe: deleteRecipe,
                          addAccountRecipe: addAccountRecipe)
        }()
        return value
    }
}

@objc extension OnePasswordDataSource: PasswordManagerDataSource {
    var autogeneratedPasswordsOnly: Bool {
        return true
    }

    func checkAvailability() -> Bool {
        if case let .cached(value) = available {
            return value
        }
        let value = OnePasswordUtils.checkUsability()
        if case .wantCache = available {
            available = .cached(value)
        }
        return value
    }

    func fetchAccounts(_ completion: @escaping ([PasswordManagerAccount]) -> ()) {
        return standardAccounts(configuration) { maybeAccount, maybeError in
            completion(maybeAccount ?? [])
        }
    }

    func add(userName: String,
             accountName: String,
             password: String,
             completion: @escaping (PasswordManagerAccount?, Error?) -> ()) {
        do {
            try OnePasswordUtils.throwIfUnusable()
            standardAdd(configuration,
                        userName: userName,
                        accountName: accountName,
                        password: password,
                        completion: completion)
        } catch {
            completion(nil, error)
        }
    }

    func resetErrors() {
        OnePasswordUtils.resetErrors()
    }

    func reload(_ completion: () -> ()) {
        configuration.listAccountsRecipe.invalidateRecipe()
        completion()
    }

    func consolidateAvailabilityChecks(_ block: () -> ()) {
        let saved = available
        defer {
            available = saved
        }
        available = .wantCache
        block()
    }
}

fileprivate extension Data {
    var smellsLike1PasswordAuthenticationError: Bool {
        guard let string = String(data: self, encoding: .utf8) else {
            return false
        }
        return string.hasPrefix("[ERROR] ") && string.contains("You are not currently signed in")
    }
}
