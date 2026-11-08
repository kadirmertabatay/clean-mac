import Foundation
import Vision

/// Groups visually very similar photos (burst shots, edited/re-saved copies).
/// Apple Vision's image feature print is computed entirely on this Mac.
enum SimilarPhotos {
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "dng", "cr2", "cr3", "nef", "arw"]
    /// Pairs below this distance count as "similar". Measurements (revision 2): resize/re-save ≈ 0.10–0.12,
    /// burst shot ≈ 0.06–0.08, different scene with similar composition ≈ 0.41. Conservative, since a false match can lead to deletion.
    static let threshold: Float = 0.30
    static let maxImages = 4000
    /// In time order, each image is compared with this many images that follow it.
    static let timeWindow = 25

    static func featurePrint(_ url: URL) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(url: url, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var d: Float = 0
        do { try a.computeDistance(&d, to: b) } catch { return nil }
        return d
    }

    /// Candidates: images in the same folder and images close in capture time. Much faster than comparing every pair.
    static func candidatePairs(_ photos: [FileEntry]) -> Set<[Int]> {
        var pairs = Set<[Int]>()
        let byTime = photos.indices.sorted { photos[$0].modifiedSort < photos[$1].modifiedSort }
        for (pos, i) in byTime.enumerated() {
            for j in byTime[(pos + 1)..<min(pos + 1 + timeWindow, byTime.count)] { pairs.insert([min(i, j), max(i, j)]) }
        }
        let byFolder = Dictionary(grouping: photos.indices) { photos[$0].url.deletingLastPathComponent().path }
        for (_, idx) in byFolder where idx.count <= 300 {
            for a in 0..<idx.count { for b in (a + 1)..<idx.count { pairs.insert([min(idx[a], idx[b]), max(idx[a], idx[b])]) } }
        }
        return pairs
    }

    static func findGroups(in entries: [FileEntry], progress: @escaping (Double) -> Void) -> [[FileEntry]] {
        let photos = Array(entries.filter { !$0.isProtected && extensions.contains($0.url.pathExtension.lowercased()) }
            .sorted { $0.size > $1.size }.prefix(maxImages))
        guard photos.count > 1 else { return [] }

        // 1. Feature prints (most of the work), in parallel.
        var prints = [VNFeaturePrintObservation?](repeating: nil, count: photos.count)
        let lock = NSLock()
        var done = 0
        DispatchQueue.concurrentPerform(iterations: photos.count) { i in
            if Task.isCancelled { return }
            let fp = autoreleasepool { featurePrint(photos[i].url) }
            lock.lock()
            prints[i] = fp
            done += 1
            let d = done
            lock.unlock()
            if d % 10 == 0 { progress(Double(d) / Double(photos.count) * 0.9) }
        }
        if Task.isCancelled { return [] }

        // 2. Compare candidate pairs and merge similar ones (union-find).
        var parent = Array(photos.indices)
        func root(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        for pair in candidatePairs(photos) {
            guard let a = prints[pair[0]], let b = prints[pair[1]], let d = distance(a, b), d < threshold else { continue }
            parent[root(pair[0])] = root(pair[1])
        }
        progress(1)
        let groups = Dictionary(grouping: photos.indices, by: root).values
            .filter { $0.count > 1 }
            .map { $0.map { photos[$0] }.sorted { $0.size > $1.size } }
        return groups.sorted { $0.dropFirst().reduce(0) { $0 + $1.size } > $1.dropFirst().reduce(0) { $0 + $1.size } }
    }
}
