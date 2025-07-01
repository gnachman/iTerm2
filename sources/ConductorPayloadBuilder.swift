//
//  ConductorPayloadBuilder.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//

class ConductorPayloadBuilder {
    private var tarJobs = [TarJob]()

    func add(localPath: URL, destination: URL) {
        for (i, _) in tarJobs.enumerated() {
            if tarJobs[i].add(local: localPath, destination: destination) {
                return
            }
        }
        tarJobs.append(TarJob(local: localPath, destination: destination))
    }

    func enumeratePayloads(_ closure: (Data, String) -> ()) {
        for job in tarJobs {
            if let data = try? job.tarballData() {
                closure(data, job.destinationBase.path)
            }
        }
    }
}
