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
    }

    struct ListItemsEntry: Codable {
        let id: String
        let title: String
        let tags: [String]?
        let trashed: String
        let ainfo: String?
    }

    private var auth: OnePasswordTokenRequester.Auth? = nil

    private func getToken() throws -> OnePasswordTokenRequester.Auth? {
        switch auth {
        case .biometric, .token(_):
            return auth
        case .none:
            break
        }
        do {
            auth = try OnePasswordTokenRequester().get()
            return auth
        } catch OPError.needsAuthentication {
            return try getToken()
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
                    return Command(command: OnePasswordUtils.pathToCLI,
                                   args: args,
                                   env: OnePasswordUtils.standardEnvironment(token: token),
                                   stdin: nil)
                },
                outputTransformer: outputTransformer)
        }

        func transform(inputs: Inputs) throws -> Outputs {
            return try dynamicRecipe.transform(inputs: inputs)
        }
    }

    private struct OnePasswordDynamicCommandRecipe<Inputs, Outputs>: Recipe {
        private let commandRecipe: CommandRecipe<Inputs, Outputs>

        init(dataSource: OnePasswordDataSource,
             inputTransformer: @escaping (Inputs, OnePasswordTokenRequester.Auth) throws -> (CommandLinePasswordDataSourceExecutableCommand),
             outputTransformer: @escaping (Output) throws -> Outputs) {
            commandRecipe = CommandRecipe<Inputs, Outputs> { inputs throws -> CommandLinePasswordDataSourceExecutableCommand in
                guard let token = try dataSource.getToken() else {
                    throw OPError.needsAuthentication
                }
                return try inputTransformer(inputs, token)
            } recovery: { error throws in
                if error as? OPError == OPError.needsAuthentication {
                    dataSource.auth = nil
                    _ = try dataSource.getToken()
                }
            } outputTransformer: { output throws -> Outputs in
                if output.returnCode != 0 {
                    if output.stderr.smellsLike1PasswordAuthenticationError {
                        throw OPError.needsAuthentication
                    }
                    throw OPError.runtime
                }
                return try outputTransformer(output)
            }
        }

        func transform(inputs: Inputs) throws -> Outputs {
            return try commandRecipe.transform(inputs: inputs)
        }
    }


    private var listAccountsRecipe: AnyRecipe<Void, [Account]> {
        // This is equivalent to running this command and then parsing out the relevant fields from
        // the output:
        //     op item list --tags iTerm2 --format json | op item get --format=json -

        let args = ["item", "list", "--format=json", "--no-color", "--tags", "iTerm2"]
        let accountsRecipe = OnePasswordBasicCommandRecipe<Void, Data>(args, dataSource: self) { $0.stdout }

        let itemsRecipe = OnePasswordDynamicCommandRecipe<Data, [Account]>(
            dataSource: self) { data, token throws -> Command in
                return Command(command: OnePasswordUtils.pathToCLI,
                               args: ["item", "get", "--format=json", "--no-color", "-"],
                               env: OnePasswordUtils.standardEnvironment(token: token),
                               stdin: data)
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

        return AnyRecipe<Void, [Account]>(PipelineRecipe(accountsRecipe, itemsRecipe))
    }

    private var getPasswordRecipe: AnyRecipe<AccountIdentifier, String> {
        return AnyRecipe(OnePasswordDynamicCommandRecipe<AccountIdentifier, String>(dataSource: self) { accountIdentifier, token in
            return Command(command: OnePasswordUtils.pathToCLI,
                           args: ["item", "get", "--field=password", accountIdentifier.value],
                           env: OnePasswordUtils.standardEnvironment(token: token),
                           stdin: nil)
        } outputTransformer: { output in
            guard let string = String(data: output.stdout, encoding: .utf8) else {
                throw OPError.badOutput
            }
            if string.hasSuffix("\r") {
                return String(string.dropLast())
            }
            return string
        })
    }

    private var setPasswordRecipe: AnyRecipe<SetPasswordRequest, Void> {
        return AnyRecipe(UnsupportedRecipe<SetPasswordRequest, Void>(reason: "1Password's CLI has no secure way to change a password."))
    }

    private var deleteRecipe: AnyRecipe<AccountIdentifier, Void> {
        return AnyRecipe(OnePasswordDynamicCommandRecipe(dataSource: self) { accountID, token in
            return Command(command: OnePasswordUtils.pathToCLI,
                           args: ["item", "delete", accountID.value],
                           env: OnePasswordUtils.standardEnvironment(token: token),
                           stdin: nil)
        } outputTransformer: { output in })
    }

    private var addAccountRecipe: AnyRecipe<AddRequest, AccountIdentifier> {
        return AnyRecipe(OnePasswordDynamicCommandRecipe(dataSource: self) { addRequest, token in
            let args = ["item",
                        "create",
                        "--category=login",
                        "--title=\(addRequest.accountName)",
                        "--tags=iTerm2",
                        "--generate-password=12,letters,digits",
                        "--format=json",
                        "username=\(addRequest.userName)"]
            return Command(command: OnePasswordUtils.pathToCLI,
                           args: args,
                           env: OnePasswordUtils.standardEnvironment(token: token),
                           stdin: nil)
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
        if OnePasswordUtils.checkUsability() == false {
            return false
        }
        return true
    }

    var accounts: [PasswordManagerAccount] {
        return standardAccounts(configuration)
    }

    func add(userName: String, accountName: String, password: String) throws -> PasswordManagerAccount {
        try OnePasswordUtils.throwIfUnusable()
        return try standardAdd(configuration, userName: userName, accountName: accountName, password: password)
    }

    func resetErrors() {
        OnePasswordUtils.resetErrors()
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
