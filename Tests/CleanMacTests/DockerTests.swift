import XCTest
@testable import CleanMac

final class DockerTests: XCTestCase {
    func testParsesDockerSizesAndDates() {
        XCTAssertEqual(DockerService.parseSize("17.1kB"), 17_100)
        XCTAssertEqual(DockerService.parseSize("68.05MB"), 68_050_000)
        XCTAssertEqual(DockerService.parseSize("1.2GB"), 1_200_000_000)
        XCTAssertEqual(DockerService.parseSize("0B"), 0)
        XCTAssertEqual(DockerService.parseSize("N/A"), 0)
        XCTAssertNotNil(DockerService.parseDate("2026-03-24 00:34:00 +0300 +03"))
    }

    func img(_ id: String, _ repo: String, _ tag: String, size: Int64 = 100, containers: Int = 0, daysAgo: Double = 0) -> DockerService.Image {
        DockerService.Image(imageID: id, repository: repo, tag: tag, size: size, containers: containers,
                            created: Date(timeIntervalSinceNow: -daysAgo * 86_400), createdSince: "")
    }

    func testAnalysisFindsRedundantObjects() {
        var s = DockerService.Snapshot()
        s.images = [
            img("sha256:a", "node", "20", size: 1_000, containers: 1, daysAgo: 1),
            img("sha256:b", "node", "18", size: 900, daysAgo: 200),            // old version, unused
            img("sha256:a", "node", "lts", size: 1_000, containers: 1, daysAgo: 1), // same image, second tag
            img("sha256:c", "<none>", "<none>", size: 300),                    // dangling
            img("sha256:d", "redis", "7", size: 200),                          // unused
        ]
        s.containers = [
            .init(id: "1", name: "web", image: "node:20", state: "running", status: "Up", size: 10, created: nil),
            .init(id: "2", name: "old", image: "node:20", state: "exited", status: "Exited", size: 20, created: nil),
        ]
        s.volumes = [.init(name: "pgdata", size: 500, links: 0, isAnonymous: false),
                     .init(name: "abc123", size: 50, links: 0, isAnonymous: true),
                     .init(name: "used", size: 70, links: 1, isAnonymous: false)]
        s.diskImageSize = 10_000

        let f = DockerService.analyze(s)
        XCTAssertEqual(f.dangling.map(\.imageID), ["sha256:c"])
        XCTAssertEqual(f.oldVersions.map(\.displayName), ["node:18"])
        XCTAssertEqual(f.duplicateTags.count, 1)
        XCTAssertEqual(Set(f.duplicateTags[0].map(\.tag)), ["20", "lts"])
        XCTAssertEqual(Set(f.unusedImages.map(\.displayName)), ["node:18", "redis:7"])
        XCTAssertEqual(f.stoppedContainers.map(\.name), ["old"])
        XCTAssertEqual(Set(f.orphanVolumes.map(\.name)), ["pgdata", "abc123"])
        // Two tags of the same image are counted once: 1000 + 900 + 300 + 200 + containers 30 + volumes 620
        XCTAssertEqual(s.usedTotal, 3_050)
        XCTAssertEqual(f.diskImageSlack, 10_000 - 3_050)
    }

    /// Only with CLEANMAC_DOCKER_TEST=1: creates, finds and deletes test objects in a real Docker.
    func testLiveDockerCleanupOfTestObjects() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLEANMAC_DOCKER_TEST"] == "1")
        try XCTSkipUnless(DockerService.isRunning, "Docker is not running")
        let docker = try XCTUnwrap(DevTools.dockerPath)
        _ = Shell.run(docker, ["pull", "-q", "hello-world"])
        _ = Shell.run(docker, ["tag", "hello-world", "hello-world:cleanmac-test"])
        _ = Shell.run(docker, ["rm", "-f", "cleanmac-test-container"])
        _ = Shell.run(docker, ["create", "--name", "cleanmac-test-container", "hello-world"])
        _ = Shell.run(docker, ["volume", "create", "cleanmac-test-vol"])

        let snap = try XCTUnwrap(DockerService.load())
        let f = DockerService.analyze(snap)
        print("[docker] image rows: \(snap.images.count), containers: \(snap.containers.count), volumes: \(snap.volumes.count), virtual disk: \(snap.diskImageSize.formattedBytes)")
        XCTAssertTrue(f.duplicateTags.contains { $0.contains { $0.tag == "cleanmac-test" } })
        let container = try XCTUnwrap(f.stoppedContainers.first { $0.name == "cleanmac-test-container" })
        let volume = try XCTUnwrap(f.orphanVolumes.first { $0.name == "cleanmac-test-vol" })
        let tag = try XCTUnwrap(snap.images.first { $0.tag == "cleanmac-test" })

        XCTAssertEqual(DockerService.removeContainers([container]).removed, 1)
        XCTAssertEqual(DockerService.removeImages([tag]).removed, 1)
        XCTAssertEqual(DockerService.removeVolumes([volume]).removed, 1)

        let after = try XCTUnwrap(DockerService.load())
        XCTAssertFalse(after.containers.contains { $0.name == "cleanmac-test-container" })
        XCTAssertFalse(after.images.contains { $0.tag == "cleanmac-test" })
        XCTAssertFalse(after.volumes.contains { $0.name == "cleanmac-test-vol" })
        XCTAssertTrue(after.images.contains { $0.repository == "hello-world" && $0.tag == "latest" }, "Only the tag should be removed")
    }
}
