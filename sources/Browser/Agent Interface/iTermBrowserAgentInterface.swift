//
//  iTermBrowserAgentInterface.swift
//  iTerm2
//
//  Created by George Nachman on 8/9/25.
//

@MainActor
class iTermBrowserAgentInterface {
    var webView: WKWebView!
    let messageHandlerName = "iTermBrowserAgent"
    private let sessionSecret: String
    #warning("DO NOT SUBMIT - CHANGE TO .defaultClient")
    var contentWorld: WKContentWorld { .page }

    init?() {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        self.sessionSecret = secret
    }

    var javascript: String {
        return iTermBrowserTemplateLoader.loadTemplate(named: "agent-interface",
                                                       type: "js",
                                                       substitutions: ["SECRET": sessionSecret])
    }

    private func js(calling name: String, payload: Data) -> String {
        return "return await window.\(messageHandlerName).\(name)('\(sessionSecret)', " + payload.lossyString + ")"
    }

    func discoverFormsInBrowser(_ args: RemoteCommand.DiscoverForms,
                                completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let obj = try await webView.callAsyncJavaScript(js(calling: "discoverForms",
                                                                   payload: try JSONEncoder().encode(args)),
                                                                contentWorld: contentWorld)
                print(obj)
                let result = obj as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func describeFormInBrowser(_ args: RemoteCommand.DescribeForm,
                               completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "describeForm",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func getFormStateInBrowser(_ args: RemoteCommand.GetFormState,
                               completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "getFormState",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func setFieldValueInBrowser(_ args: RemoteCommand.SetFieldValue,
                                completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "setFieldValue",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func chooseOptionInBrowser(_ args: RemoteCommand.ChooseOption,
                               completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "chooseOption",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func toggleCheckboxInBrowser(_ args: RemoteCommand.ToggleCheckbox,
                                 completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "toggleCheckbox",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func uploadFileInBrowser(_ args: RemoteCommand.UploadFile,
                             completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "uploadFile",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func clickNodeInBrowser(_ args: RemoteCommand.ClickNode,
                            completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "clickNode",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    private class PendingSubmit {
        var closure: ((String, String) throws -> ())?
        var task: Task<Void, Never>?

        init(closure: @escaping (String, String) throws -> ()) {
            self.closure = closure
        }

        func execute(_ message: String, _ status: String) {
            if let closure {
                self.closure = nil
                task?.cancel()
                try? closure(message, status)
            }
        }
    }

    private var pendingSubmit: PendingSubmit?

    func submitFormInBrowser(_ args: RemoteCommand.SubmitForm,
                             completion: @escaping (String, String) throws -> ()) rethrows {
        pendingSubmit?.execute("", "Another task submitted the form")
        pendingSubmit = PendingSubmit(closure: completion)
        let task = Task { @MainActor in
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "submitForm",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    finishFormSubmission(result, "Completed successfully")
                } else {
                    finishFormSubmission("Internal error", "Completed successfully")
                }
            } catch {
                finishFormSubmission(error.localizedDescription, "Operation failed or page navigation occurred (which is not actually an error)")
            }
        }
        pendingSubmit?.task = task
    }

    func willNavigate() {
        finishFormSubmission("The form submission completed", "Completed successfully")
    }


    private func finishFormSubmission(_ message: String, _ status: String) {
        if let pendingSubmit {
            self.pendingSubmit = nil
            pendingSubmit.execute(message, status)
        }
    }

    func validateFormInBrowser(_ args: RemoteCommand.ValidateForm,
                               completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "validateForm",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func inferSemanticsInBrowser(_ args: RemoteCommand.InferSemantics,
                                 completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "inferSemantics",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func focusFieldInBrowser(_ args: RemoteCommand.FocusField,
                             completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "focusField",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func blurFieldInBrowser(_ args: RemoteCommand.BlurField,
                            completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "blurField",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func scrollIntoViewInBrowser(_ args: RemoteCommand.ScrollIntoView,
                                 completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "scrollIntoView",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func detectChallengeInBrowser(_ args: RemoteCommand.DetectChallenge,
                                  completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "detectChallenge",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }

    func mapNodesForActionsInBrowser(_ args: RemoteCommand.MapNodesForActions,
                                     completion: @escaping (String, String) throws -> ()) rethrows {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(js(calling: "mapNodesForActions",
                                                                      payload: try JSONEncoder().encode(args)),
                                                                   contentWorld: contentWorld) as? String
                if let result {
                    try? completion(result, "Completed successfully")
                } else {
                    try? completion("Internal error", "Operation failed")
                }
            } catch {
                try? completion(error.localizedDescription, "Operation failed")
            }
        }
    }
}
