// Mythica Studio — native bridge for the Mac app.
// Links photos and videos WHERE THEY ARE (nothing is copied):
//   • Apple Photos through PhotoKit (by local identifier, incl. iCloud-only items)
//   • files on disk / external drives by path
// Media reach the page through a private URL scheme:
//   mythmedia://ph/thumb?id=…   mythmedia://ph/full?id=…   mythmedia://ph/video?id=…
//   mythmedia://f/thumb?p=…     mythmedia://f/full?p=…     mythmedia://f/raw?p=…   (raw supports Range for video)
// Page → app: window.webkit.messageHandlers.mythica.postMessage(JSON.stringify({myth:"op", rid:n, …}))
// App → page: window.MYTH_native({rid:n, data:…})
import Cocoa
import WebKit
import Photos
import AVFoundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

let kImageExt: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "webp", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"]
let kVideoExt: Set<String> = ["mov", "mp4", "m4v", "avi", "mts", "m2ts", "3gp", "mkv", "webm"]
let kPassExt: Set<String> = ["jpg", "jpeg", "png", "gif", "webp"]

func mythJPEG(_ cg: CGImage, _ q: Double = 0.84) -> Data? {
    let rep = NSBitmapImageRep(cgImage: cg)
    return rep.representation(using: .jpeg, properties: [.compressionFactor: q])
}

func mythMime(_ ext: String) -> String {
    switch ext.lowercased() {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "mov": return "video/quicktime"
    case "mp4", "m4v": return "video/mp4"
    case "webm": return "video/webm"
    default: return "application/octet-stream"
    }
}

// MARK: - media URL scheme
final class MythMedia: NSObject, WKURLSchemeHandler {
    static let shared = MythMedia()
    let imgMgr = PHCachingImageManager()
    private var live = Set<ObjectIdentifier>()
    private let lock = NSLock()
    private let work = DispatchQueue(label: "myth.media", qos: .userInitiated, attributes: .concurrent)
    private let thumbCache = NSCache<NSString, NSData>()

    override init() { super.init(); thumbCache.countLimit = 1500 }

    func isLive(_ t: WKURLSchemeTask) -> Bool { lock.lock(); defer { lock.unlock() }; return live.contains(ObjectIdentifier(t)) }
    func finish(_ t: WKURLSchemeTask) { lock.lock(); live.remove(ObjectIdentifier(t)); lock.unlock() }

    func webView(_ webView: WKWebView, start t: WKURLSchemeTask) {
        lock.lock(); live.insert(ObjectIdentifier(t)); lock.unlock()
        guard let url = t.request.url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { fail(t, 400); return }
        var q: [String: String] = [:]
        for it in comps.queryItems ?? [] { q[it.name] = it.value ?? "" }
        let host = comps.host ?? "", path = comps.path
        let range = t.request.value(forHTTPHeaderField: "Range")
        if let cached = thumbCache.object(forKey: url.absoluteString as NSString), path == "/thumb" {
            send(t, cached as Data, "image/jpeg"); return
        }
        work.async {
            if host == "ph", let id = q["id"] {
                switch path {
                case "/thumb": self.photo(t, id, 480, true)
                case "/full": self.photo(t, id, 2400, false)
                case "/video": self.photoVideo(t, id, range)
                default: self.fail(t, 404)
                }
            } else if host == "f", let p = q["p"] {
                let fu = URL(fileURLWithPath: p)
                let ext = fu.pathExtension.lowercased()
                guard kImageExt.contains(ext) || kVideoExt.contains(ext) else { self.fail(t, 403); return }
                guard FileManager.default.isReadableFile(atPath: p) else { self.fail(t, 404); return }
                switch path {
                case "/thumb": self.fileThumb(t, fu)
                case "/full":
                    if kPassExt.contains(ext) || kVideoExt.contains(ext) { self.raw(t, fu, range) } else { self.fileFull(t, fu) }
                case "/raw": self.raw(t, fu, range)
                default: self.fail(t, 404)
                }
            } else { self.fail(t, 400) }
        }
    }
    func webView(_ webView: WKWebView, stop t: WKURLSchemeTask) { finish(t) }

    func send(_ t: WKURLSchemeTask, _ data: Data, _ mime: String, status: Int = 200, extra: [String: String] = [:]) {
        DispatchQueue.main.async {
            guard self.isLive(t), let url = t.request.url else { return }
            var h = ["Content-Type": mime, "Content-Length": "\(data.count)", "Cache-Control": "max-age=86400", "Access-Control-Allow-Origin": "*"]
            for (k, v) in extra { h[k] = v }
            let r = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: h)!
            t.didReceive(r); t.didReceive(data); t.didFinish(); self.finish(t)
        }
    }
    func fail(_ t: WKURLSchemeTask, _ code: Int) {
        DispatchQueue.main.async {
            guard self.isLive(t) else { return }
            t.didFailWithError(NSError(domain: "mythmedia", code: code)); self.finish(t)
        }
    }

    // Apple Photos still image (thumb or large)
    func photo(_ t: WKURLSchemeTask, _ id: String, _ px: CGFloat, _ cache: Bool) {
        guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { fail(t, 404); return }
        let o = PHImageRequestOptions()
        o.deliveryMode = .highQualityFormat; o.resizeMode = .fast; o.isNetworkAccessAllowed = true; o.isSynchronous = false
        imgMgr.requestImage(for: a, targetSize: CGSize(width: px, height: px), contentMode: .aspectFit, options: o) { img, info in
            if let deg = info?[PHImageResultIsDegradedKey] as? Bool, deg { return }
            guard let img = img, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil), let d = mythJPEG(cg, cache ? 0.78 : 0.86) else { self.fail(t, 404); return }
            if cache, let u = t.request.url { self.thumbCache.setObject(d as NSData, forKey: u.absoluteString as NSString) }
            self.send(t, d, "image/jpeg")
        }
    }
    // Apple Photos video: stream the original file (downloads from iCloud if needed)
    func photoVideo(_ t: WKURLSchemeTask, _ id: String, _ range: String?) {
        guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { fail(t, 404); return }
        let o = PHVideoRequestOptions(); o.isNetworkAccessAllowed = true; o.deliveryMode = .highQualityFormat; o.version = .current
        imgMgr.requestAVAsset(forVideo: a, options: o) { av, _, _ in
            if let u = (av as? AVURLAsset)?.url { self.work.async { self.raw(t, u, range) } } else { self.fail(t, 415) }
        }
    }
    func fileThumb(_ t: WKURLSchemeTask, _ u: URL) {
        let req = QLThumbnailGenerator.Request(fileAt: u, size: CGSize(width: 480, height: 480), scale: 1, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            if let cg = rep?.cgImage, let d = mythJPEG(cg, 0.78) {
                if let k = t.request.url { self.thumbCache.setObject(d as NSData, forKey: k.absoluteString as NSString) }
                self.send(t, d, "image/jpeg")
            } else { self.fail(t, 415) }
        }
    }
    func fileFull(_ t: WKURLSchemeTask, _ u: URL) {
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { fail(t, 415); return }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2400]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary), let d = mythJPEG(cg, 0.86) else { fail(t, 415); return }
        send(t, d, "image/jpeg")
    }
    // byte ranges so <video> can seek through big files without loading them whole
    func raw(_ t: WKURLSchemeTask, _ u: URL, _ range: String?) {
        guard let fh = try? FileHandle(forReadingFrom: u) else { fail(t, 404); return }
        defer { try? fh.close() }
        let size = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.int64Value ?? 0
        let mime = mythMime(u.pathExtension)
        var start: Int64 = 0, end: Int64 = size - 1
        var partial = false
        if let r = range, r.hasPrefix("bytes=") {
            let parts = r.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            if parts.count == 2 {
                if let s = Int64(parts[0]) { start = s; if let e = Int64(parts[1]) { end = min(e, size - 1) } }
                else if let n = Int64(parts[1]) { start = max(0, size - n) }
                partial = true
            }
        }
        if !partial && size > 8_000_000 && kVideoExt.contains(u.pathExtension.lowercased()) { end = min(size - 1, 4_000_000 - 1); partial = true }   // let the player ask for the rest
        if start > end || start >= size { fail(t, 416); return }
        let len = Int(end - start + 1)
        try? fh.seek(toOffset: UInt64(start))
        let data = (try? fh.read(upToCount: len)) ?? Data()
        if partial {
            send(t, data, mime, status: 206, extra: ["Content-Range": "bytes \(start)-\(end)/\(size)", "Accept-Ranges": "bytes"])
        } else {
            send(t, data, mime, extra: ["Accept-Ranges": "bytes"])
        }
    }
}

// MARK: - page bridge (save/load, Photos queries, folders, exports)
final class Mythica {
    static let shared = Mythica()
    weak var web: WKWebView?
    var root: URL?
    let bg = DispatchQueue(label: "myth.bridge", qos: .userInitiated)
    var dir: URL?          // ~/Documents/Mythica Studio (set by the app)
    var dataURL: URL? { dir?.appendingPathComponent("mythica-studio-data.json") }

    func reply(_ frame: WKFrameInfo?, _ rid: Any?, _ payload: Any) {
        let obj: [String: Any] = ["rid": rid ?? NSNull(), "data": payload]
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: []), let s = String(data: d, encoding: .utf8) else { return }
        let js = "window.MYTH_native&&window.MYTH_native(\(s))"
        DispatchQueue.main.async {
            guard let w = self.web else { return }
            if let f = frame { w.evaluateJavaScript(js, in: f, in: .page, completionHandler: nil) } else { w.evaluateJavaScript(js, completionHandler: nil) }
        }
    }
    func authString(_ s: PHAuthorizationStatus? = nil) -> String {
        switch s ?? PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return "yes"
        case .limited: return "limited"
        case .denied, .restricted: return "no"
        default: return "ask"
        }
    }
    func loadData() -> Any {
        guard let u = dataURL, let d = try? Data(contentsOf: u), let o = try? JSONSerialization.jsonObject(with: d) else { return NSNull() }
        return o
    }

    func handle(_ o: [String: Any], frame: WKFrameInfo?) {
        let op = o["myth"] as? String ?? "", rid = o["rid"]
        switch op {
        case "hello":
            reply(frame, rid, ["native": true, "photos": authString(), "data": loadData(), "version": "standalone-1.0"])
        case "auth":
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in self.reply(frame, rid, self.authString(s)) }
        case "counts":
            bg.async {
                var c: [String: [Int]] = [:], days: [String: Int] = [:]
                let f = DateFormatter(); f.dateFormat = "yyyy-MM"
                let fd = DateFormatter(); fd.dateFormat = "yyyy-MM-dd"
                let all = PHAsset.fetchAssets(with: PHFetchOptions())
                all.enumerateObjects { a, _, _ in
                    guard let d = a.creationDate else { return }
                    let k = f.string(from: d); var v = c[k] ?? [0, 0]
                    if a.mediaType == .video { v[1] += 1 } else { v[0] += 1 }
                    c[k] = v
                    days[fd.string(from: d), default: 0] += 1
                }
                self.reply(frame, rid, ["months": c, "days": days])
            }
        case "albums":
            bg.async {
                let fd = DateFormatter(); fd.dateFormat = "yyyy-MM-dd"
                var out: [[Any]] = []
                for kind in [PHAssetCollectionType.album] {
                    PHAssetCollection.fetchAssetCollections(with: kind, subtype: .any, options: nil).enumerateObjects { col, _, _ in
                        let fo = PHFetchOptions(); fo.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                        let a = PHAsset.fetchAssets(in: col, options: fo)
                        guard a.count > 0, let d0 = a.firstObject?.creationDate, let d1 = a.lastObject?.creationDate else { return }
                        out.append([col.localizedTitle ?? "Album", a.count, fd.string(from: d0), fd.string(from: d1)])
                    }
                }
                self.reply(frame, rid, out)
            }
        case "query":
            let from = (o["from"] as? NSNumber)?.doubleValue ?? 0, to = (o["to"] as? NSNumber)?.doubleValue ?? 0
            let limit = (o["limit"] as? NSNumber)?.intValue ?? 4000
            bg.async {
                let fo = PHFetchOptions()
                fo.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", Date(timeIntervalSince1970: from / 1000) as NSDate, Date(timeIntervalSince1970: to / 1000) as NSDate)
                fo.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                fo.fetchLimit = limit
                var out: [[Any]] = []
                PHAsset.fetchAssets(with: fo).enumerateObjects { a, _, _ in
                    let ms = (a.creationDate?.timeIntervalSince1970 ?? 0) * 1000
                    let loc = a.location?.coordinate
                    out.append([a.localIdentifier, ms, a.mediaType == .video ? 1 : 0, loc.map { $0.latitude as Any } ?? NSNull(), loc.map { $0.longitude as Any } ?? NSNull(), a.isFavorite ? 1 : 0, a.duration])
                }
                self.reply(frame, rid, out)
            }
        case "save":
            guard let s = o["data"] as? String, let u = dataURL, let dd = dir else { reply(frame, rid, false); return }
            bg.async {
                try? FileManager.default.createDirectory(at: dd.appendingPathComponent("backups"), withIntermediateDirectories: true)
                let ok = (try? s.data(using: .utf8)!.write(to: u, options: .atomic)) != nil
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                try? s.data(using: .utf8)!.write(to: dd.appendingPathComponent("backups/mythica-studio-data-\(f.string(from: Date())).json"), options: .atomic)
                self.reply(frame, rid, ok)
            }
        case "load":
            reply(frame, rid, loadData())
        case "pickFolder":
            DispatchQueue.main.async {
                let p = NSOpenPanel()
                p.title = "Link a photo / video folder"; p.message = "Mythica Studio will show what's inside — nothing gets copied."
                p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
                if p.runModal() == .OK, let u = p.url { self.reply(frame, rid, u.path) } else { self.reply(frame, rid, NSNull()) }
            }
        case "scan":
            let path = o["path"] as? String ?? ""
            bg.async { self.reply(frame, rid, self.scan(path)) }
        case "export":
            guard let name = o["name"] as? String, let text = o["text"] as? String, let dd = dir else { reply(frame, rid, false); return }
            let sub = (o["folder"] as? String) ?? ""
            let images = o["images"] as? [[String: Any]] ?? []
            bg.async {
                let folder = sub.isEmpty ? dd.appendingPathComponent("exports") : dd.appendingPathComponent("exports/\(sub)")
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = folder.appendingPathComponent(name)
                try? text.data(using: .utf8)!.write(to: target, options: .atomic)
                // cover images for website cards (the only place Studio writes image files, on purpose)
                let g = DispatchGroup()
                for im in images {
                    guard let file = im["file"] as? String, let ref = im["ref"] as? [String: Any] else { continue }
                    g.enter()
                    self.renderRef(ref, 1600) { d in
                        if let d = d { try? d.write(to: folder.appendingPathComponent(file), options: .atomic) }
                        g.leave()
                    }
                }
                g.wait()
                DispatchQueue.main.async { if o["reveal"] as? Bool ?? true { NSWorkspace.shared.activateFileViewerSelecting([target]) } }
                self.reply(frame, rid, target.path)
            }
        case "reveal":
            if let p = o["path"] as? String {
                DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
            } else if o["photos"] != nil {
                DispatchQueue.main.async {
                    if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") { NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil) }
                }
            }
            reply(frame, rid, true)
        case "openFile":
            if let p = o["path"] as? String { DispatchQueue.main.async { NSWorkspace.shared.open(URL(fileURLWithPath: p)) } }
            reply(frame, rid, true)
        case "exists":
            let ps = o["paths"] as? [String] ?? []
            reply(frame, rid, ps.map { FileManager.default.fileExists(atPath: $0) })
        default:
            reply(frame, rid, ["error": "unknown op \(op)"])
        }
    }

    // every photo / video under a folder, with the best date we can find
    func scan(_ path: String) -> Any {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return ["missing": true] }
        let base = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        guard let en = fm.enumerator(at: base, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return ["missing": true] }
        let exif = DateFormatter(); exif.dateFormat = "yyyy:MM:dd HH:mm:ss"
        var out: [[Any]] = []
        for case let u as URL in en {
            if out.count >= 30000 { break }
            let name = u.lastPathComponent
            if name.hasPrefix("._") { continue }
            let ext = u.pathExtension.lowercased()
            let isImg = kImageExt.contains(ext), isVid = kVideoExt.contains(ext)
            if !isImg && !isVid { continue }
            let rv = try? u.resourceValues(forKeys: Set(keys))
            var date = rv?.creationDate ?? rv?.contentModificationDate
            if isImg, let src = CGImageSourceCreateWithURL(u as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
               let ex = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let s = ex[kCGImagePropertyExifDateTimeOriginal] as? String, let d = exif.date(from: s) { date = d }
            let mod = rv?.contentModificationDate
            if let d = date, let m = mod, m < d { date = m }   // copies often get a newer "created" date
            out.append([u.path, (date?.timeIntervalSince1970 ?? 0) * 1000, isVid ? 1 : 0, rv?.fileSize ?? 0])
        }
        return ["files": out]
    }

    func renderRef(_ ref: [String: Any], _ px: CGFloat, _ done: @escaping (Data?) -> Void) {
        let k = ref["k"] as? String ?? ""
        if k == "ph", let id = ref["id"] as? String, let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
            let o = PHImageRequestOptions(); o.deliveryMode = .highQualityFormat; o.isNetworkAccessAllowed = true; o.isSynchronous = false
            MythMedia.shared.imgMgr.requestImage(for: a, targetSize: CGSize(width: px, height: px), contentMode: .aspectFit, options: o) { img, info in
                if let deg = info?[PHImageResultIsDegradedKey] as? Bool, deg { return }
                done(img.flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }.flatMap { mythJPEG($0, 0.86) })
            }
            return
        }
        var path = ref["p"] as? String ?? ""
        if k == "loc", let r = root { path = r.appendingPathComponent(path).path }
        let u = URL(fileURLWithPath: path)
        if kVideoExt.contains(u.pathExtension.lowercased()) {
            let req = QLThumbnailGenerator.Request(fileAt: u, size: CGSize(width: px, height: px), scale: 1, representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in done(rep.flatMap { mythJPEG($0.cgImage, 0.86) }) }
            return
        }
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { done(nil); return }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: px]
        done(CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).flatMap { mythJPEG($0, 0.86) })
    }
}
