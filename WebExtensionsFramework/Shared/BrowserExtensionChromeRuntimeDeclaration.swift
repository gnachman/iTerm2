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
        VariableArgsFunction("sendMessage", returns: AnyJSONCodable.self)
        ConfigurableProperty("lastError", getter: "return undefined;")
    }
}

