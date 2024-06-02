class WebRequest {
    constructor(headers, method, body, url) {
        this.headers = headers;
        this.method = method;
        this.body = body
        this.url = url;
    }
}

class WebResponse {
    constructor(data, error) {
        this.data = data;
        this.error = error
    }

    toJSON() {
        return {
            data: this.data,
            error: this.error
        };
    }
}

async function request(jsonString) {
    const jsonParsed = JSON.parse(jsonString);
    const webRequest = new WebRequest(jsonParsed.headers, jsonParsed.method, jsonParsed.body, jsonParsed.url);
    const promise = new Promise((resolve, reject) => {
        performHTTPRequest(webRequest.method, webRequest.url, webRequest.headers, webRequest.body, (responseBody, error) => {
            if (error != "") {
                reject(JSON.stringify(new WebResponse(responseBody, error).toJSON()));
            } else {
                resolve(JSON.stringify(new WebResponse(responseBody, error).toJSON()));
            }
        });
    });

    return await promise;
}

function version() {
    return JSON.stringify("1.1");
}
