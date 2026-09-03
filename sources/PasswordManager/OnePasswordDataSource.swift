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
    private let tag: String?
    private let tagToExclude: String?


    private var requester: OnePasswordTokenRequester?
    private static var haveCheckedAccounts = false

    init(browser: Bool) {
        tag = browser ? nil : "iTerm2"
        tagToExclude = browser ? "iTerm2" : nil
    }

    private func asyncGetToken(_ completion: @escaping (Result<OnePasswordTokenRequester.Auth, Error>) -> ()) {
        if Self.haveCheckedAccounts {
            asyncReallyGetToken(completion)
            return
        }
        fetchAccountListAndMakeUserPick(forceSelection: false, completion)
    }

    private func fetchAccountListAndMakeUserPick(forceSelection: Bool,
                                                 _ completion: @escaping (Result<OnePasswordTokenRequester.Auth, Error>) -> ()) {
        DLog("Checking account list")
        OnePasswordAccountPicker.asyncGetAccountList { [weak self] result in
            DLog("result=\(result)")
            guard let self else {
                DLog("I got dealloced")
                return
            }
            Self.haveCheckedAccounts = true

            switch result {
            case .success(let allAccounts):
                DLog("\(allAccounts)")
                let accounts = allAccounts.filter {
                    $0.email != nil && $0.account_uuid != nil
                }
                DLog("\(accounts)")
                if accounts.count > 1 {
                    let name = iTermAdvancedSettingsModel.onePasswordAccount()!
                    DLog("name=\(name)")
                    if forceSelection || !accounts.anySatisfies({ $0.email == name || $0.account_uuid == name || $0.user_uuid == name }) {
                        OnePasswordAccountPicker.askUserToSelect(from: accounts)
                    }
                }
                asyncReallyGetToken(completion)
            case .failure:
                asyncReallyGetToken(completion)
            }
        }
    }

    private func asyncReallyGetToken(_ completion: @escaping (Result<OnePasswordTokenRequester.Auth, Error>) -> ()) {
        switch auth {
        case .biometric, .token(_):
            completion(.success(auth!))
            return
        case .none:
            break
        }
        if requester != nil {
            RLog("WARNING: Overwriting existing token requester.")
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
            case .success(let acquired):
                // Cache the token so later stages/operations reuse it instead of re-prompting.
                // The setPasswordRecipe is a two-stage SequenceRecipe (op item get, then op item
                // edit); without caching, a non-biometric setup would pop the master-password
                // modal once per stage. An expired token surfaces as needsAuthentication, whose
                // recovery clears this and re-auths.
                self.auth = acquired
                completion(result)
            case .failure:
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

        func transformAsync(context: RecipeExecutionContext,
                            inputs: Inputs,
                            completion: @escaping (Outputs?, Error?) -> ()) {
            dynamicRecipe.transformAsync(context: context,
                                         inputs: inputs,
                                         completion: completion)
        }
    }

    private struct OnePasswordDynamicCommandRecipe<Inputs, Outputs>: Recipe {
        private let commandRecipe: AsyncCommandRecipe<Inputs, Outputs>

        init(dataSource: OnePasswordDataSource,
             inputTransformer: @escaping (Inputs, OnePasswordTokenRequester.Auth) throws -> (CommandLinePasswordDataSourceExecutableCommand),
             outputTransformer: @escaping (Output) throws -> Outputs) {

            commandRecipe = AsyncCommandRecipe<Inputs, Outputs> { (context, inputs, completion) in
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
                    alert.messageText = String(localized: "OnePasswordDataSource_Timeout", defaultValue: "Timeout", comment: "Alert title in transformAsync")
                    alert.informativeText = String(localized: "OnePasswordDataSource_1PasswordTookTooLongToRespond", defaultValue: "1Password took too long to respond.", comment: "Alert explanatory text in transformAsync")
                    alert.addButton(withTitle: String(localized: "COMMON_OK", defaultValue: "OK", comment: "Button title in transformAsync"))
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

        func transformAsync(context: RecipeExecutionContext,
                            inputs: Inputs,
                            completion: @escaping (Outputs?, Error?) -> ()) {
            commandRecipe.transformAsync(context: context,
                                         inputs: inputs,
                                         completion: completion)
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
        let tagToExclude = self.tagToExclude
        var args = ["item", "list", "--format=json", "--no-color"]
        if let tag {
            args.append(contentsOf: ["--tags", tag])
        }
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
                    var type: String?
                    var value: String?
                    var totp: String?
                }
                struct Item: Codable {
                    var id: String
                    var title: String
                    var fields: [Field]
                    var tags: [String]?
                }
                guard let phonyJson = String(data: output.stdout, encoding: .utf8) else {
                    throw OPError.runtime
                }
                let json = "[" + phonyJson.replacingOccurrences(of: "}\n{", with: "},\n{") + "]"
                let items = try JSONDecoder().decode([Item].self, from: json.data(using: .utf8)!)
                return items.compactMap {
                    if let tagToExclude, $0.tags?.contains(tagToExclude) == true {
                        return nil
                    }
                    let username: String?
                    if let field = $0.fields.first(where: { field in
                        field.id == "username"
                    }) {
                        username = field.value
                    } else {
                        username = nil
                    }
                    let hasOTP = $0.fields.anySatisfies { field in field.type == "OTP" }
                    let otpDisabled = $0.tags?.contains("iTerm2-no-otp") ?? false
                    return Account(identifier: CommandLinePasswordDataSource.AccountIdentifier(value: $0.id),
                                   userName: username ?? "",
                                   accountName: $0.title,
                                   hasOTP: hasOTP,
                                   sendOTP: hasOTP ? !otpDisabled : false)
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

            let getValue = { (fieldName: String) -> String? in
                let desiredField = item.fields.first { field in
                    field.id == fieldName
                }
                guard let value = desiredField?.value else {
                    return nil
                }
                if value.hasSuffix("\r") {
                    return String(value.dropLast())
                }
                return value
            }
            // Accept credential because the user may have added an API credential through the
            // 1password UI and manually tagged it with iTerm2
            let password = getValue("password") ?? getValue("credential")
            guard let password else {
                 throw OPError.runtime
            }
            let otp = {
                let otpField = item.fields.first { field in
                    field.type == "OTP"
                }
                return otpField?.totp
            }()
            return Password(password: password, otp: otp)
        })
    }

    // Patches the changed fields into a full `op item get --format=json` payload, leaving
    // every other field (empty notes, OTP, custom) exactly as op returned it. op item edit
    // applies the whole template, so the round-trip is lossless.
    private static func patchedItemJSON(_ original: Data, request: SetPasswordRequest) throws -> Data {
        guard var obj = try JSONSerialization.jsonObject(with: original) as? [String: Any] else {
            throw OPError.badOutput
        }
        if let title = request.newAccountName {
            obj["title"] = title
        }
        var fields = obj["fields"] as? [[String: Any]] ?? []
        var patchedUserName = false
        var patchedPassword = false
        for i in fields.indices {
            let purpose = (fields[i]["purpose"] as? String)?.uppercased()
            let id = (fields[i]["id"] as? String)?.lowercased()
            if (purpose == "USERNAME" || id == "username"), let userName = request.newUserName {
                fields[i]["value"] = userName
                patchedUserName = true
            } else if (purpose == "PASSWORD" || id == "password"), let password = request.newPassword {
                fields[i]["value"] = password
                patchedPassword = true
            }
        }
        // If the item has no field of the needed kind (e.g. a login created in the UI with no
        // username field, or an item whose `fields` array is absent), op item edit would apply
        // the template and silently ignore the change. Append a properly-typed field so the new
        // value is actually written instead of a success-with-no-op.
        if let userName = request.newUserName, !patchedUserName {
            fields.append(["id": "username", "type": "STRING", "purpose": "USERNAME", "label": "username", "value": userName])
        }
        if let password = request.newPassword, !patchedPassword {
            fields.append(["id": "password", "type": "CONCEALED", "purpose": "PASSWORD", "label": "password", "value": password])
        }
        if !fields.isEmpty {
            obj["fields"] = fields
        }
        return try JSONSerialization.data(withJSONObject: obj)
    }

    private var setPasswordRecipe: AnyRecipe<SetPasswordRequest, Void> {
        // Edit in place by round-tripping the item's JSON: `op item get <id> --format=json`,
        // patch the changed fields, then pipe the template to `op item edit <id>` over stdin.
        // The password never appears on the command line. Requires a modern op (see
        // pathToCLI, which selects the newest installed CLI); op 2.5.x ignores piped edits.
        let getRecipe = OnePasswordDynamicCommandRecipe(dataSource: self) { (request: SetPasswordRequest, token) in
            // --reveal so concealed fields (the password) carry their real value in the JSON.
            // The template is re-submitted whole, so an unchanged password must round-trip as
            // its actual value; without --reveal a title-only edit could blank it.
            InteractiveCommandRequest(
                command: OnePasswordUtils.pathToCLI,
                args: ["item", "get", request.accountIdentifier.value, "--reveal", "--format=json"],
                env: OnePasswordUtils.standardEnvironment(token: token))
        } outputTransformer: { output -> Data in
            output.stdout
        }
        let editRecipe = OnePasswordDynamicCommandRecipe(dataSource: self) { (input: (SetPasswordRequest, Data), token) in
            let (request, itemJSON) = input
            let patched = try Self.patchedItemJSON(itemJSON, request: request)
            var command = InteractiveCommandRequest(
                command: OnePasswordUtils.pathToCLI,
                args: ["item", "edit", request.accountIdentifier.value],
                env: OnePasswordUtils.standardEnvironment(token: token))
            command.callbacks = InteractiveCommandRequest.Callbacks(
                callbackQueue: InteractiveCommandRequest.ioQueue,
                handleStdout: nil,
                handleStderr: nil,
                handleTermination: nil,
                didLaunch: { writing in
                    writing.write(patched) {
                        writing.closeForWriting()
                    }
                })
            return command
        } outputTransformer: { _ in }
        return AnyRecipe(SequenceRecipe(getRecipe, editRecipe))
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
        let tag = self.tag
        // Create from a JSON template piped over stdin so the user-supplied password stays
        // off the command line (secure), instead of `--generate-password`.
        return AnyRecipe(OnePasswordDynamicCommandRecipe(dataSource: self) { (addRequest: AddRequest, token) in
            let template: [String: Any] = [
                "title": addRequest.accountName,
                "category": "LOGIN",
                "fields": [
                    ["id": "username", "type": "STRING", "purpose": "USERNAME", "label": "username", "value": addRequest.userName],
                    ["id": "password", "type": "CONCEALED", "purpose": "PASSWORD", "label": "password", "value": addRequest.password],
                ],
            ]
            let templateData = try JSONSerialization.data(withJSONObject: template)
            var args = ["item", "create", "--format=json"]
            if let tag {
                args.append("--tags=\(tag)")
            }
            args.append("-")  // read the template from stdin
            var request = InteractiveCommandRequest(
                command: OnePasswordUtils.pathToCLI,
                args: args,
                env: OnePasswordUtils.standardEnvironment(token: token))
            request.callbacks = InteractiveCommandRequest.Callbacks(
                callbackQueue: InteractiveCommandRequest.ioQueue,
                handleStdout: nil,
                handleStderr: nil,
                handleTermination: nil,
                didLaunch: { writing in
                    writing.write(templateData) {
                        writing.closeForWriting()
                    }
                })
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
    @objc var name: String { "1Password" }
    @objc var canResetConfiguration: Bool { false }
    @objc func resetConfiguration() { }

    var autogeneratedPasswordsOnly: Bool {
        // Add and edit now accept a user-supplied password via a stdin JSON template.
        return false
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

    // Resolve the op CLI versions off the main thread so the synchronous checkAvailability that
    // follows reads the warm cache instead of spawning `op -v` on the run loop.
    func prepareAvailability(_ completion: @escaping () -> ()) {
        OnePasswordUtils.resolveVersionsInBackground(completion)
    }

    func fetchAccounts(context: RecipeExecutionContext, completion: @escaping ([any PasswordManagerAccount]) -> ()) {
        return standardAccounts(context: context,
                                configuration: configuration) { maybeAccount, maybeError in
            completion(maybeAccount ?? [])
        }
    }

    var addAccountToggleDescriptions: [[String: Any]]? { nil }
    // `op item edit` renames title/username in place.
    var supportsInPlaceEdit: Bool { true }
    // A modern op edits the password securely via a stdin template (see setPasswordRecipe).
    var canEditPassword: Bool { true }
    // The create template writes the password field verbatim, so a blank field would store an
    // empty password. Require one (previously guaranteed by --generate-password).
    var requiresPasswordForAdd: Bool { true }

    @objc(addUserName:accountName:password:flags:context:completion:)
    func add(userName: String,
             accountName: String,
             password: String,
             flags: [String: Bool],
             context: RecipeExecutionContext,
             completion: @escaping (PasswordManagerAccount?, Error?) -> ()) {
        // 1Password has no Add Account toggles, so flags is ignored.
        do {
            try OnePasswordUtils.throwIfUnusable()
            standardAdd(configuration,
                        userName: userName,
                        accountName: accountName,
                        password: password,
                        context: context,
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

    func toggleShouldSendOTP(context: RecipeExecutionContext,
                             account pmAccount: PasswordManagerAccount,
                             completion: @escaping (PasswordManagerAccount?, Error?) -> ()) {
        guard let account = pmAccount as? CommandLineProvidedAccount else {
            it_fatalError()
        }
        let recipe = if account.sendOTP {
            mutateTagRecipe(accountID: account.identifier) { tags in
                Array(Set(tags).union(Set(["iTerm2-no-otp"])))
            }
        } else {
            mutateTagRecipe(accountID: account.identifier) { tags in
                Array(Set(tags).subtracting(Set(["iTerm2-no-otp"])))
            }
        }
        let configuration = self.configuration
        recipe.transformAsync(context: context, inputs: ()) { _, error in
            if let error {
                completion(nil, error)
                return
            }
            let updated = CommandLineProvidedAccount(identifier: account.identifier,
                                                     accountName: account.accountName,
                                                     userName: account.userName,
                                                     hasOTP: account.hasOTP,
                                                     sendOTP: !account.sendOTP,
                                                     configuration: configuration)
            completion(updated, nil)
        }
    }

    @nonobjc
    private func getTagsRecipe(accountID: String) -> AnyRecipe<Void, [String]> {
        return AnyRecipe(OnePasswordDynamicCommandRecipe(dataSource: self, inputTransformer: { _, token in
            return CommandRequestWithInput(
                command: OnePasswordUtils.pathToCLI,
                args: ["item", "get", "--format=json", "--no-color", accountID],
                env: OnePasswordUtils.standardEnvironment(token: token),
                input: Data())
        }, outputTransformer: { output throws -> [String] in
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
                var tags: [String]?
            }
            guard let phonyJson = String(data: output.stdout, encoding: .utf8) else {
                throw OPError.runtime
            }
            let json = "[" + phonyJson.replacingOccurrences(of: "}\n{", with: "},\n{") + "]"
            let items = try JSONDecoder().decode([Item].self, from: json.data(using: .utf8)!)
            return items.first?.tags ?? []
        }))
    }

    @nonobjc
    private func mutateTagRecipe(accountID: String, mutator: @escaping ([String]) -> ([String])) -> AnyRecipe<Void, Void> {
        let mutateTagsRecipe = AnyRecipe(OnePasswordDynamicCommandRecipe<[String], Void>(dataSource: self, inputTransformer: { tags, token in
            let updatedTags = mutator(tags)

            return CommandRequestWithInput(
                command: OnePasswordUtils.pathToCLI,
                args: ["item", "edit", accountID, "--tags", updatedTags.joined(separator: ",")],
                env: OnePasswordUtils.standardEnvironment(token: token),
                input: Data())
        }, outputTransformer: { _ in }))
        return AnyRecipe(PipelineRecipe(getTagsRecipe(accountID: accountID),
                                        mutateTagsRecipe))
    }

    var supportsMultipleAccounts: Bool {
        true
    }

    func switchAccount(completion: @escaping () -> ()) {
        fetchAccountListAndMakeUserPick(forceSelection: true) { result in
            DLog("\(result)")
            completion()
        }
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
