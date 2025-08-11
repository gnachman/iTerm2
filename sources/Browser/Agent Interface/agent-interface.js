(function() {
    'use strict';
    console.log("[agent-interface] Loading browser agent interface");
    const secret = '{{SECRET}}';

    {{INCLUDE:agent-utils.js}}
    {{INCLUDE:agent-impl.js}}
    {{INCLUDE:graph-discovery.js}}

    console.log("[agent-interface] Creating AgentImpl instance");
    const impl = new AgentImpl()

    console.log("[agent-interface] Defining API methods");
    const api = {
        discoverForms: async (sessionSecret, payload) => {
            console.log("[agent-interface] discoverForms called with secret check");
            if (sessionSecret != secret) { 
                console.warn("[agent-interface] discoverForms: Invalid session secret");
                return; 
            }
            console.log("[agent-interface] discoverForms: calling impl with payload:", payload);
            const obj = await impl.discoverForms(payload);
            console.log("[agent-interface] Result is", obj);
            const str = JSON.stringify(obj);
            console.log("[agent-interface] Stringified is", str);
            return str;
        },
        describeForm: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.describeForm(payload));
        },
        getFormState: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.getFormState(payload));
        },
        setFieldValue: async (sessionSecret, payload) => {
            console.log("[agent-interface] setFieldValue called");
            if (sessionSecret != secret) { 
                console.warn("[agent-interface] setFieldValue: Invalid session secret");
                return; 
            }
            console.log("[agent-interface] setFieldValue: calling impl with payload:", payload);
            return JSON.stringify(await impl.setFieldValue(payload));
        },
        chooseOption: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.chooseOption(payload));
        },
        toggleCheckbox: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.toggleCheckbox(payload));
        },
        uploadFile: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.uploadFile(payload));
        },
        clickNode: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.clickNode(payload));
        },
        submitForm: async (sessionSecret, payload) => {
            console.log("[agent-interface] submitForm called");
            if (sessionSecret != secret) { 
                console.warn("[agent-interface] submitForm: Invalid session secret");
                return; 
            }
            console.log("[agent-interface] submitForm: calling impl with payload:", payload);
            return JSON.stringify(await impl.submitForm(payload));
        },
        validateForm: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.validateForm(payload));
        },
        inferSemantics: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.inferSemantics(payload));
        },
        focusField: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.focusField(payload));
        },
        blurField: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.blurField(payload));
        },
        scrollIntoView: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.scrollIntoView(payload));
        },
        detectChallenge: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.detectChallenge(payload));
        },
        mapNodesForActions: async (sessionSecret, payload) => {
            if (sessionSecret != secret) { return; }
            return JSON.stringify(await impl.mapNodesForActions(payload));
        },
    }
    console.log("[agent-interface] Freezing API and attaching to window");
    Object.freeze(api);
    Object.defineProperty(window, 'iTermBrowserAgent', {
        value: api,
        writable: false,
        configurable: false,
        enumerable: true
    });
    console.log("[agent-interface] Browser agent interface loaded successfully");

 })()
