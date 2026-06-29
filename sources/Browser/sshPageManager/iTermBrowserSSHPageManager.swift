//
//  iTermBrowserSSHPageManager.swift
//  iTerm2
//
//  Created by George Nachman on 8/11/25.
//

import Foundation
import WebKit

@MainActor
class iTermBrowserSSHPageManager {
    private class Job {
        let oid: ObjectIdentifier
        private var task: Task<Void, Never>?
        private let mutex = Mutex()

        var stopped: Bool { task?.isCancelled != false }

        init(oid: ObjectIdentifier, closure: @escaping (Job) async -> ()) {
            self.oid = oid
            self.task = Task {
                await closure(self)
            }
        }

        func stop() {
            mutex.sync {
                task?.cancel()
                task = nil
            }
        }
    }
    private var jobs = [ObjectIdentifier: Job]()

    deinit {
        for job in jobs.values {
            job.stop()
        }
    }

    func handleURLSchemeTask(_ urlSchemeTask: WKURLSchemeTask, url: URL) -> Bool {
        let oid = ObjectIdentifier(urlSchemeTask)
        DLog("\(oid): handleURLSchemeTask called with \(url)")
        guard url.scheme == iTermBrowserSchemes.ssh else {
            return false
        }

        guard let conductor = ConductorRegistry.instance.conductors(for: url).first else {
            let html = iTermBrowserTemplateLoader.load(
                template: "ssh-page-no-conductor.html",
                substitutions: ["HOST": url.host ?? "(nil)"]).lossyData
            let response = URLResponse(
                url: url,
                mimeType: "text/html",
                expectedContentLength: html.count,
                textEncodingName: "utf-8")
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(html)
            urlSchemeTask.didFinish()
            return true
        }

        let job = Job(oid: oid) { [weak self] job in
            await Self.doStream(urlSchemeTask: urlSchemeTask,
                                job: job,
                                url: url,
                                conductor: conductor)
            self?.jobs.removeValue(forKey: oid)
        }
        if !job.stopped {
            jobs[oid] = job
        }
        return true
    }

    private static func doStream(urlSchemeTask: WKURLSchemeTask,
                                 job: Job,
                                 url: URL,
                                 conductor: Conductor) async {
        let path = SCPPath()
        path.path = url.path
        path.hostname = url.host
        path.username = url.user
        let stream = conductor.streamDownload(path: path)
        do {
            let info = try await conductor.stat(url.path)
            let ext = url.path.pathExtension
            let response = URLResponse(
                url: url,
                mimeType: mimeType(for: ext) ?? "application/octet-stream",
                expectedContentLength: info.size ?? -1,
                textEncodingName: "utf-8")
            DLog("\(job.oid): Response's mime type is \(response.mimeType ?? "(nil)") and expectedContentLength is \(response.expectedContentLength)")
            if job.stopped {
                return
            }
            urlSchemeTask.didReceive(response)
            for try await data in stream {
                if job.stopped {
                    return
                }
                DLog("\(job.oid): did receive \(data.count) bytes")
                urlSchemeTask.didReceive(data)
            }
            if job.stopped {
                return
            }
            DLog("\(job.oid): did finish")
            urlSchemeTask.didFinish()
        } catch {
            if job.stopped {
                return
            }
            DLog("\(job.oid): did fail \(error)")
            urlSchemeTask.didFailWithError(error)
        }
    }

    func stop(urlSchemeTask: WKURLSchemeTask) {
        let oid = ObjectIdentifier(urlSchemeTask)
        DLog("\(oid): stop called")
        jobs[oid]?.stop()
        jobs.removeValue(forKey: oid)
    }
}
