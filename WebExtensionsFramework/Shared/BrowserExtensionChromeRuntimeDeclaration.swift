//
//  BrowserExtensionChromeRuntimeDeclaration.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/6/25.
//

func makeChromeRuntime(inputs: APIInputs) -> Namespace {
    // NOTE: When you change this, you must re-run `swift run APIGenerator` to generate new Swift protocols.
    Namespace("runtime") {
        Constant("id", inputs.extensionId)
        AsyncFunction("getPlatformInfo", returns: PlatformInfo.self) {}
        AsyncFunction("sendMessage", returns: AnyJSONCodable.self) {
            Argument("arg1", type: AnyJSONCodable.self)
            Argument("arg2", type: AnyJSONCodable.self)
            Argument("arg3", type: AnyJSONCodable.self)
        }
    }
}

