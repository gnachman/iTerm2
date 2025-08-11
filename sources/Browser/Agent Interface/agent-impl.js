
class AgentImpl {
    constructor() {
        console.log("[agent-impl] AgentImpl constructor called");
        if (!window.iTermGraphDiscovery) {
            console.warn("[agent-impl] iTermGraphDiscovery bridge is missing");
        } else {
            console.log("[agent-impl] iTermGraphDiscovery bridge found");
        }
    }

    _wrapCall(funcName, argsObject) {
        console.log("[agent-impl] _wrapCall called with funcName:", funcName, "args:", argsObject);
        // Inline call into the target frame; returns JSON-serializable value.
        const payload = JSON.stringify({ funcName, argsObject });
        console.log("[agent-impl] _wrapCall payload:", payload);
        return `
        (function() {
            console.log("[agent-runtime] Executing wrapped call for: ${funcName}");
            try {
                console.log("[agent-runtime] Runtime found, parsing payload");
                var p = ${payload};
                console.log("[agent-runtime] Switching on funcName:", p.funcName);
                switch (p.funcName) {
                case "discoverForms":
                    console.log("[agent-runtime] Calling getForms with visibility:", p.argsObject.visibility || "visible");
                    var result = { ok: true, forms: getForms(p.argsObject.visibility || "visible") };
                    console.log("[agent-runtime] getForms result:", result);
                    return result;
                case "describeForm":
                    console.log("[agent-runtime] Calling describeForm with formId:", p.argsObject.formId);
                    var result = Object.assign({ ok: true }, describeForm(p.argsObject.formId, !!p.argsObject.includeOptions, !!p.argsObject.includeAria, !!p.argsObject.includeCss));
                    console.log("[agent-runtime] describeForm result:", result);
                    return result;
                case "getFormState":
                    console.log("[agent-runtime] Calling currentFormValues with formId:", p.argsObject.formId);
                    var result = Object.assign({ ok: true }, currentFormValues(p.argsObject.formId, !!p.argsObject.maskSecrets));
                    console.log("[agent-runtime] currentFormValues result:", result);
                    return result;
                case "setFieldValue":
                    console.log("[agent-runtime] Calling setValue with fieldId:", p.argsObject.fieldId, "value:", p.argsObject.value);
                    var result = Object.assign({ ok: true }, setValue(p.argsObject.fieldId, p.argsObject));
                    console.log("[agent-runtime] setValue result:", result);
                    return result;
                case "chooseOption":
                    console.log("[agent-runtime] Calling choose with fieldId:", p.argsObject.fieldId, "choice:", p.argsObject.choice);
                    var result = Object.assign({ ok: true }, choose(p.argsObject.fieldId, p.argsObject.by || "value", p.argsObject.choice, !!p.argsObject.deselectOthers));
                    console.log("[agent-runtime] choose result:", result);
                    return result;
                case "toggleCheckbox":
                    console.log("[agent-runtime] Calling setCheckbox with fieldId:", p.argsObject.fieldId, "checked:", p.argsObject.checked);
                    var result = Object.assign({ ok: true }, setCheckbox(p.argsObject.fieldId, !!p.argsObject.checked));
                    console.log("[agent-runtime] setCheckbox result:", result);
                    return result;
                case "uploadFile":
                    console.log("[agent-runtime] uploadFile not supported");
                    return { ok: false, error: { code: "unsupported", message: "File upload requires native bridge" } };
                case "clickNode":
                    console.log("[agent-runtime] Calling clickNode with nodeId:", p.argsObject.nodeId);
                    var result = Object.assign({ ok: true }, clickNode(p.argsObject.nodeId, p.argsObject.button || "left", p.argsObject.clickCount || 1, !!p.argsObject.ensureVisible));
                    console.log("[agent-runtime] clickNode result:", result);
                    return result;
                case "submitForm":
                    console.log("[agent-runtime] Calling submitForm with formId:", p.argsObject.formId);
                    var result = Object.assign({ ok: true }, submitForm(p.argsObject.formId, p.argsObject.submitterNodeId || null));
                    console.log("[agent-runtime] submitForm result:", result);
                    return result;
                case "validateForm":
                    console.log("[agent-runtime] Calling validateForm with formId:", p.argsObject.formId);
                    var result = Object.assign({ ok: true }, validateForm(p.argsObject.formId));
                    console.log("[agent-runtime] validateForm result:", result);
                    return result;
                case "inferSemantics":
                    console.log("[agent-runtime] Calling inferSemantics with formId:", p.argsObject.formId);
                    var result = Object.assign({ ok: true }, inferSemantics(p.argsObject.formId, p.argsObject.locale || "en-US"));
                    console.log("[agent-runtime] inferSemantics result:", result);
                    return result;
                case "focusField":
                    console.log("[agent-runtime] Calling focusField with fieldId:", p.argsObject.fieldId);
                    var result = Object.assign({ ok: true }, focusField(p.argsObject.fieldId));
                    console.log("[agent-runtime] focusField result:", result);
                    return result;
                case "blurField":
                    console.log("[agent-runtime] Calling blurField with fieldId:", p.argsObject.fieldId);
                    var result = Object.assign({ ok: true }, blurField(p.argsObject.fieldId));
                    console.log("[agent-runtime] blurField result:", result);
                    return result;
                case "scrollIntoView":
                    console.log("[agent-runtime] Calling scrollIntoViewById with nodeId:", p.argsObject.nodeId);
                    var result = Object.assign({ ok: true }, scrollIntoViewById(p.argsObject.nodeId, p.argsObject.align || "nearest"));
                    console.log("[agent-runtime] scrollIntoViewById result:", result);
                    return result;
                case "detectChallenge":
                    console.log("[agent-runtime] Calling detectChallengeSnapshot");
                    var result = Object.assign({ ok: true }, detectChallengeSnapshot(p.argsObject.formId || null));
                    console.log("[agent-runtime] detectChallengeSnapshot result:", result);
                    return result;
                case "mapNodesForActions":
                    console.log("[agent-runtime] Calling mapActionNodes");
                    var result = Object.assign({ ok: true }, mapActionNodes(p.argsObject.formId || null));
                    console.log("[agent-runtime] mapActionNodes result:", result);
                    return result;
                default:
                    console.error("[agent-runtime] Unknown funcName:", p.funcName);
                    return { error: { code: "bad_argument", message: "Unknown funcName" } };
                }
            } catch (e) {
                console.error("[agent-runtime] Exception in wrapped call:", e);
                return { error: { code: "exception", message: String(e && e.message || e) } };
            }
        })();
        `;
    }

    _evaluateInFrame(frameId, js, timeoutMs) {
        console.log("[agent-impl] _evaluateInFrame called with frameId:", frameId, "timeout:", timeoutMs);
        console.log("[agent-impl] _evaluateInFrame JS code length:", js.length);
        return new Promise((resolve) => {
            window.iTermGraphDiscovery.evaluateInFrame(frameId, js, (value, error) => {
                if (error) {
                    console.error("[agent-impl] _evaluateInFrame error:", error);
                    resolve({ ok: false, error: { code: "eval_error", message: String(error) } });
                    return;
                }
                console.log("[agent-impl] _evaluateInFrame success, result:", value);
                resolve(value || { ok: false, error: { code: "null", message: "No result" } });
            }, timeoutMs);
        });
    }

    async _withFrame(payload, fnName, args) {
        console.log("[agent-impl] _withFrame called with fnName:", fnName, "frameId:", payload?.frameId, "args:", args);
        if (!payload || !payload.frameId) {
            console.error("[agent-impl] _withFrame missing frameId");
            return { ok: false, error: { code: "bad_argument", message: "frameId is required" } };
        }
        const js = this._wrapCall(fnName, args);
        const res = await this._evaluateInFrame(payload.frameId, js, payload.timeoutMs || 2000);
        console.log("[agent-impl] _withFrame result:", res);
        return res;
    }

    async discoverForms(payload) {
        console.log("[agent-impl] discoverForms called with payload:", payload);
        if (!payload || !payload.frameId) {
            console.log("[agent-impl] discoverForms: No specific frameId, evaluating in all frames");
            // Run across all frames and merge
            return new Promise((resolve) => {
                const visibility = (payload && payload.visibility) || "visible";
                const timeout = payload && payload.timeoutMs || 2000;
                console.log("[agent-impl] discoverForms: calling evaluateInAll with visibility:", visibility, "timeout:", timeout);
                
                window.iTermGraphDiscovery.evaluateInAll(this._wrapCall("discoverForms", { visibility }), (results) => {
                    console.log("[agent-impl] discoverForms: evaluateInAll results:", results);
                    const out = [];
                    for (const [fid, val] of Object.entries(results || {})) {
                        console.log("[agent-impl] discoverForms: processing frame", fid, "with result:", val);
                        if (val && val.ok && Array.isArray(val.forms)) {
                            out.push({ frameId: fid, forms: val.forms });
                        }
                    }
                    console.log("[agent-impl] discoverForms: final merged result:", { ok: true, frames: out });
                    resolve({ ok: true, frames: out });
                }, timeout);
            });
        }
        console.log("[agent-impl] discoverForms: using specific frameId:", payload.frameId);
        return this._withFrame(payload, "discoverForms", { visibility: payload.visibility || "visible" });
    }

    async describeForm(payload) {
        console.log("[agent-impl] describeForm called with payload:", payload);
        if (!payload || !payload.frameId || !payload.formId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and formId are required" } };
        }
        return this._withFrame(payload, "describeForm", {
            formId: payload.formId,
            includeOptions: payload.includeOptions !== false,
            includeAria: payload.includeAria !== false,
            includeCss: !!payload.includeCss
        });
    }

    async getFormState(payload) {
        console.log("[agent] getFormState");
        if (!payload || !payload.frameId || !payload.formId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and formId are required" } };
        }
        return this._withFrame(payload, "getFormState", {
            formId: payload.formId,
            maskSecrets: payload.maskSecrets !== false
        });
    }

    async setFieldValue(payload) {
        console.log("[agent-impl] setFieldValue called with payload:", payload);
        if (!payload || !payload.frameId || !payload.fieldId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and fieldId are required" } };
        }
        return this._withFrame(payload, "setFieldValue", {
            fieldId: payload.fieldId,
            value: payload.value,
            mode: payload.mode || "set",
            clearFirst: !!payload.clearFirst,
            delayMsPerChar: payload.delayMsPerChar || 0,
            ensureVisible: payload.ensureVisible !== false,
            selectAfter: !!payload.selectAfter
        });
    }

    async chooseOption(payload) {
        console.log("[agent] chooseOption");
        if (!payload || !payload.frameId || !payload.fieldId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and fieldId are required" } };
        }
        return this._withFrame(payload, "chooseOption", {
            fieldId: payload.fieldId,
            by: payload.by || "value",
            choice: payload.choice,
            deselectOthers: payload.deselectOthers !== false
        });
    }

    async toggleCheckbox(payload) {
        console.log("[agent] toggleCheckbox");
        if (!payload || !payload.frameId || !payload.fieldId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and fieldId are required" } };
        }
        return this._withFrame(payload, "toggleCheckbox", {
            fieldId: payload.fieldId,
            checked: !!payload.checked
        });
    }

    async uploadFile(payload) {
        console.log("[agent] uploadFile");
        // JS alone cannot set <input type="file"> for security reasons.
        // Return an explicit unsupported error; native layer should handle.
        return { ok: false, error: { code: "unsupported", message: "uploadFile requires native integration" } };
    }

    async clickNode(payload) {
        console.log("[agent] clickNode");
        if (!payload || !payload.frameId || !payload.nodeId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and nodeId are required" } };
        }
        try {
            return this._withFrame(payload, "clickNode", {
                nodeId: payload.nodeId,
                ensureVisible: payload.ensureVisible !== false,
                button: payload.button || "left",
                clickCount: payload.clickCount || 1
            });
        } catch (e) {
            console.log("[agent] clickNode execution failed: ", e.toString(), e);
            throw e;
        }
    }

    async submitForm(payload) {
        console.log("[agent-impl] submitForm called with payload:", payload);
        if (!payload || !payload.frameId || !payload.formId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and formId are required" } };
        }
        
        const wait = !!payload.wait;
        const timeoutMs = payload.timeoutMs || 10000;
        console.log("[agent-impl] submitForm: wait =", wait, "timeoutMs =", timeoutMs);
        
        // Submit the form first
        console.log("[agent-impl] submitForm: submitting form first");
        const submitResult = await this._withFrame(payload, "submitForm", {
            formId: payload.formId,
            submitterNodeId: payload.submitterNodeId || null
        });
        console.log("[agent-impl] submitForm: form submission result:", submitResult);
        
        // If submit failed or no wait needed, return immediately
        if (!submitResult.ok || !wait) {
            console.log("[agent-impl] submitForm: returning immediately (ok =", submitResult.ok, ", wait =", wait, ")");
            return submitResult;
        }
        
        // Wait for same-document change
        console.log("[agent-impl] submitForm: starting wait for same-document change");
        const waitJs = `
        (async function() {
            try {
                if (typeof waitSameDocumentChange !== 'function') {
                    return { ok: false, error: { code: "function_missing", message: "waitSameDocumentChange not available" } };
                }
                const result = await waitSameDocumentChange(${timeoutMs});
                return { ok: true, wait_result: result };
            } catch (e) {
                return { ok: false, error: { code: "exception", message: String(e && e.message || e) } };
            }
        })();
        `;
        
        const waitResult = await this._evaluateInFrame(payload.frameId, waitJs, timeoutMs + 1000);
        console.log("[agent-impl] submitForm: wait result:", waitResult);
        if (waitResult.ok && waitResult.wait_result) {
            console.log("[agent-impl] submitForm: wait succeeded, combining results");
            return Object.assign(submitResult, { wait_result: waitResult.wait_result });
        } else {
            console.log("[agent-impl] submitForm: wait failed or timed out");
            return Object.assign(submitResult, { wait_result: { satisfied: false, error: waitResult.error } });
        }
    }

    async validateForm(payload) {
        console.log("[agent] validateForm");
        if (!payload || !payload.frameId || !payload.formId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and formId are required" } };
        }
        return this._withFrame(payload, "validateForm", { formId: payload.formId });
    }

    async inferSemantics(payload) {
        console.log("[agent] inferSemantics");
        if (!payload || !payload.frameId || !payload.formId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and formId are required" } };
        }
        return this._withFrame(payload, "inferSemantics", {
            formId: payload.formId,
            locale: payload.locale || "en-US"
        });
    }

    async focusField(payload) {
        console.log("[agent] focusField");
        if (!payload || !payload.frameId || !payload.fieldId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and fieldId are required" } };
        }
        return this._withFrame(payload, "focusField", { fieldId: payload.fieldId });
    }

    async blurField(payload) {
        console.log("[agent] blurField");
        if (!payload || !payload.frameId || !payload.fieldId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and fieldId are required" } };
        }
        return this._withFrame(payload, "blurField", { fieldId: payload.fieldId });
    }

    async scrollIntoView(payload) {
        console.log("[agent] scrollIntoView");
        if (!payload || !payload.frameId || !payload.nodeId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId and nodeId are required" } };
        }
        return this._withFrame(payload, "scrollIntoView", {
            nodeId: payload.nodeId,
            align: payload.align || "nearest"
        });
    }


    async detectChallenge(payload) {
        console.log("[agent] detectChallenge");
        if (!payload || !payload.frameId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId is required" } };
        }
        return this._withFrame(payload, "detectChallenge", { formId: payload.formId || null });
    }

    async mapNodesForActions(payload) {
        console.log("[agent] mapNodesForActions");
        if (!payload || !payload.frameId) {
            return { ok: false, error: { code: "bad_argument", message: "frameId is required" } };
        }
        return this._withFrame(payload, "mapNodesForActions", { formId: payload.formId || null });
    }
}
