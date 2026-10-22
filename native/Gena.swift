// Gena — native macOS wrapper (WKWebView, no Electron, no dependencies)
// Required Notice: Copyright (c) 2026 Mintay Misgano (https://github.com/skabone)
// Licensed under the PolyForm Noncommercial License 1.0.0
//
// Loads the hosted Gena so the app stays current and cloud sync works.
// The app keeps its own private storage, separate from any browser.
// V6.9: a narrow bridge lets the hosted page read and write the Mac's calendars through EventKit.

import Cocoa
import WebKit
import EventKit

let APP_URL = "https://skabone.github.io/gena/"
let HOME_HOST = "skabone.github.io"

/* ---------- V6.9 Mac Calendar bridge (M1, M2) ----------
   One message handler, "genaCal", answers only the hosted Gena page in the main frame (https, skabone.github.io,
   /gena/). Requests are JSON-shaped objects, checked field by field before anything touches EventKit; answers are
   JSON strings. Nothing is evaluated from the page, and the app keeps no event data: each answer is built from
   EventKit when asked and handed to the page. The only script the app runs in the page is a fixed line that
   tells it the calendars changed or the app came back to the front. */
let BRIDGE_NAME = "genaCal"
let BRIDGE_OPS: Set<String> = ["status", "requestAccess", "calendars", "events", "save", "remove", "openSettings"]
let BRIDGE_SPANS: Set<String> = ["this", "future", "all"]
let BRIDGE_MAX_DAYS = 420.0, BRIDGE_MAX_EVENTS = 5000
let DAY_MS = 86_400_000.0

// the page a request may come from: Gena's hosted origin, main frame, under /gena/
func bridgeAllowed(isMainFrame: Bool, scheme: String?, host: String?, port: Int, path: String?) -> Bool {
    guard isMainFrame, scheme == "https", host == HOME_HOST, port == 0 || port == 443 else { return false }
    let p = path ?? ""
    return p == "/gena" || p.hasPrefix("/gena/")
}

struct BridgeSet {
    var title: String?, loc: String?, notes: String?, cal: String?, allDay: Bool?, start: Double?, end: Double?
    var hasTime: Bool { return start != nil }
}
struct BridgeRequest {
    var op: String
    var from = 0.0, to = 0.0                       // events
    var eid: String? = nil, occ: Double? = nil      // save, remove: the occurrence
    var span = "this", stamp: Double? = nil
    var set = BridgeSet()                           // save
}

private func isBool(_ v: Any?) -> Bool { if let n = v as? NSNumber { return CFGetTypeID(n) == CFBooleanGetTypeID() }; return false }
private func num(_ v: Any?) -> Double? {
    guard let n = v as? NSNumber, !isBool(n) else { return nil }
    let d = n.doubleValue
    return d.isFinite && d > 0 && d < 7_258_118_400_000 ? d : nil   // 1970 to 2200
}
private func str(_ v: Any?, max: Int) -> String? { guard let s = v as? String, s.count <= max else { return nil }; return s }
private func onlyKeys(_ d: [String: Any], _ keys: Set<String>) -> Bool { return Set(d.keys).isSubset(of: keys) }

// every request is checked here, before EventKit sees it; a request that is not exactly the expected shape is refused
func parseBridgeRequest(_ body: Any) -> (BridgeRequest?, String?) {
    guard let d = body as? [String: Any], onlyKeys(d, ["op", "args"]), let op = d["op"] as? String, BRIDGE_OPS.contains(op) else { return (nil, "unknown request") }
    var r = BridgeRequest(op: op)
    let a: [String: Any]
    if d["args"] == nil || d["args"] is NSNull { a = [:] } else if let x = d["args"] as? [String: Any] { a = x } else { return (nil, "bad arguments") }
    switch op {
    case "status", "requestAccess", "calendars", "openSettings":
        if !a.isEmpty { return (nil, "bad arguments") }
    case "events":
        guard onlyKeys(a, ["from", "to"]), let f = num(a["from"]), let t = num(a["to"]), t > f, t - f <= BRIDGE_MAX_DAYS * DAY_MS else { return (nil, "bad range") }
        r.from = f; r.to = t
    case "save":
        guard onlyKeys(a, ["event"]), let e = a["event"] as? [String: Any], onlyKeys(e, ["eid", "occ", "span", "stamp", "set"]) else { return (nil, "bad event") }
        if e["eid"] != nil { guard let id = str(e["eid"], max: 512), !id.isEmpty, let o = num(e["occ"]) else { return (nil, "bad event id") }; r.eid = id; r.occ = o }
        else if e["occ"] != nil { return (nil, "bad event id") }
        if e["span"] != nil { guard let s = e["span"] as? String, BRIDGE_SPANS.contains(s) else { return (nil, "bad span") }; r.span = s }
        if e["stamp"] != nil { guard let s = num(e["stamp"]) else { return (nil, "bad stamp") }; r.stamp = s }
        guard let s = e["set"] as? [String: Any], !s.isEmpty, onlyKeys(s, ["title", "loc", "notes", "cal", "allDay", "start", "end"]) else { return (nil, "bad fields") }
        if s["title"] != nil { guard let t = str(s["title"], max: 500), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (nil, "bad title") }; r.set.title = t }
        if s["loc"] != nil { guard let t = str(s["loc"], max: 500) else { return (nil, "bad place") }; r.set.loc = t }
        if s["notes"] != nil { guard let t = str(s["notes"], max: 5000) else { return (nil, "bad notes") }; r.set.notes = t }
        if s["cal"] != nil { guard let t = str(s["cal"], max: 256), !t.isEmpty else { return (nil, "bad calendar") }; r.set.cal = t }
        // a time is the three together: all day or not, start and end
        let timeKeys = ["allDay", "start", "end"].filter { s[$0] != nil }
        if !timeKeys.isEmpty {
            guard timeKeys.count == 3, isBool(s["allDay"]), let st = num(s["start"]), let en = num(s["end"]), en >= st, en - st <= BRIDGE_MAX_DAYS * DAY_MS else { return (nil, "bad time") }
            r.set.allDay = (s["allDay"] as! NSNumber).boolValue; r.set.start = st; r.set.end = en
        }
        if r.eid == nil && (r.set.cal == nil || r.set.title == nil || !r.set.hasTime || r.span != "this") { return (nil, "a new event needs a calendar, a title and a time") }
    case "remove":
        guard onlyKeys(a, ["eid", "occ", "span", "stamp"]), let id = str(a["eid"], max: 512), !id.isEmpty, let o = num(a["occ"]) else { return (nil, "bad event id") }
        r.eid = id; r.occ = o
        if a["span"] != nil { guard let s = a["span"] as? String, BRIDGE_SPANS.contains(s) else { return (nil, "bad span") }; r.span = s }
        if a["stamp"] != nil { guard let s = num(a["stamp"]) else { return (nil, "bad stamp") }; r.stamp = s }
    default: return (nil, "unknown request")
    }
    return (r, nil)
}

// the page's side of the bridge: added at document start, main frame only, and only on Gena's own page
let BRIDGE_JS = """
(function(){
  if (window.top !== window || location.protocol !== "https:" || location.hostname !== "skabone.github.io" || !/^\\/gena(\\/|$)/.test(location.pathname)) return;
  var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.genaCal;
  if (!h || window.GenaNative) return;
  function call(op, args){ return h.postMessage({op: op, args: args || {}}).then(function(t){ return JSON.parse(t); }); }
  Object.defineProperty(window, "GenaNative", {value: Object.freeze({ v: 1,
    status: function(){ return call("status"); },
    requestAccess: function(){ return call("requestAccess"); },
    calendars: function(){ return call("calendars"); },
    events: function(from, to){ return call("events", {from: from, to: to}); },
    save: function(ev){ return call("save", {event: ev}); },
    remove: function(r){ return call("remove", r); },
    openSettings: function(){ return call("openSettings"); } })});
})();
"""
let BRIDGE_CHANGED_JS = "window.dispatchEvent(new CustomEvent('gena-native',{detail:'changed'}))"
let BRIDGE_ACTIVE_JS = "window.dispatchEvent(new CustomEvent('gena-native',{detail:'active'}))"
// V6.6.1 GD-075 F4: a download was saved to Downloads, or could not be; fixed lines like the two above (no file name goes back)
let DOWNLOAD_SAVED_JS = "window.dispatchEvent(new CustomEvent('gena-native',{detail:'saved'}))"
let DOWNLOAD_FAILED_JS = "window.dispatchEvent(new CustomEvent('gena-native',{detail:'savefail'}))"

/* ---------- V6.6.1 GD-075 F4: downloads (⋯ → Export, the tasks CSV, an .ics) ----------
   The page saves a file the way a browser does, a link with `download` to a blob it made. WKWebView does nothing with that unless
   the app takes it as a download (macOS 11.3+). Only Gena's own page, in the main frame, may start one (the bridge's gate), and only
   for a blob or data link it made itself; the file goes to ~/Downloads under the name the page suggests, made safe, never over a
   file already there ("name (1).ext", "name (2).ext", ...) */
func downloadAllowed(isMainFrame: Bool, scheme: String?, host: String?, port: Int, path: String?, linkScheme: String?) -> Bool {
    guard let l = linkScheme?.lowercased(), l == "blob" || l == "data" else { return false }
    return bridgeAllowed(isMainFrame: isMainFrame, scheme: scheme, host: host, port: port, path: path)
}
// a file name the page suggested, as one plain name: no folders, no hidden or empty name, at most 120 characters and
// NAME_MAX_BYTES of UTF-8 (V25 finding 5: APFS takes 255 bytes, and freeFileName may add " (n)" or a UUID); a cut takes whole
// characters off the name before its extension, so ".json" stays
let NAME_MAX_BYTES = 200
func safeFileName(_ s: String) -> String {
    var n = s.components(separatedBy: CharacterSet(charactersIn: "/\\:")).last ?? ""
    n = String(n.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
    while n.hasPrefix(".") { n.removeFirst() }
    let fits = { (x: String) -> Bool in x.count <= 120 && x.utf8.count <= NAME_MAX_BYTES }
    if !fits(n) {
        let ns = n as NSString, ext = ns.pathExtension, keep = !ext.isEmpty && ext.count <= 16 && ext.utf8.count <= 32
        let tail = keep ? "." + ext : ""
        var stem = keep ? ns.deletingPathExtension : n
        while !stem.isEmpty && !fits(stem + tail) { stem.removeLast() }
        n = (stem.isEmpty ? "Gena download" : stem) + tail
    }
    return n.isEmpty ? "Gena download" : n
}
// the name itself when it is free, else "name (1).ext", "name (2).ext", ... (exists answers for a name in the folder)
func freeFileName(_ name: String, exists: (String) -> Bool) -> String {
    if !exists(name) { return name }
    let ns = name as NSString, ext = ns.pathExtension, stem = ext.isEmpty ? name : ns.deletingPathExtension
    for i in 1...9999 { let c = "\(stem) (\(i))" + (ext.isEmpty ? "" : ".\(ext)"); if !exists(c) { return c } }
    return "\(stem) \(UUID().uuidString)" + (ext.isEmpty ? "" : ".\(ext)")
}

// GD-072 (1): a meeting with guests is changed in the Calendar app only (a change or a delete from here could email them): save and remove refuse it
func guestRefusal(_ guests: Int) -> [String: Any]? { return guests > 0 ? ["ok": false, "code": "guests"] : nil }
// V9 review finding 2: a span is read in pieces of at most BRIDGE_MAX_DAYS, back to back, from its first day to its last
func guestWindows(_ from: Date, _ to: Date) -> [(Date, Date)] {
    var w: [(Date, Date)] = [], d = from
    while d < to { let e = min(d.addingTimeInterval(BRIDGE_MAX_DAYS * 86400), to); w.append((d, e)); d = e }
    return w
}

func jsonText(_ o: Any) -> String {
    guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return "{\"ok\":false,\"code\":\"failed\"}" }
    return s
}
private func ms(_ d: Date?) -> Double { return d.map { ($0.timeIntervalSince1970 * 1000).rounded() } ?? 0 }
private func clip(_ s: String?, _ n: Int) -> String { guard let s = s else { return "" }; return s.count > n ? String(s.prefix(n)) : s }
private func hexOf(_ c: NSColor?) -> String {
    guard let c = c?.usingColorSpace(.sRGB) else { return "" }
    let v = [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
    return String(format: "#%02x%02x%02x", v[0], v[1], v[2])
}

final class CalendarBridge: NSObject, WKScriptMessageHandlerWithReply {
    let store = EKEventStore()
    let queue = DispatchQueue(label: "com.mintaymisgano.gena.calendar")   // EventKit work never runs on the window's thread
    weak var web: WKWebView?
    private var changed: DispatchWorkItem?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.changed?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.tell(BRIDGE_CHANGED_JS) }
            self.changed = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)   // a burst of changes is one refresh
        }
    }

    // a fixed line, and only into Gena's own page
    func tell(_ js: String) {
        guard let w = web, let u = w.url, bridgeAllowed(isMainFrame: true, scheme: u.scheme, host: u.host, port: u.port ?? 0, path: u.path) else { return }
        w.evaluateJavaScript(js, completionHandler: nil)
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        let f = message.frameInfo, o = f.securityOrigin
        guard bridgeAllowed(isMainFrame: f.isMainFrame, scheme: o.protocol, host: o.host, port: o.port, path: f.request.url?.path) else { replyHandler(nil, "not allowed"); return }
        let (req, err) = parseBridgeRequest(message.body)
        guard let r = req else { replyHandler(nil, err ?? "bad request"); return }
        let done: (Any) -> Void = { o in let t = jsonText(o); DispatchQueue.main.async { replyHandler(t, nil) } }
        switch r.op {
        case "status": done(["ok": true, "access": access()])
        case "requestAccess": requestAccess(done)
        case "openSettings":
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { NSWorkspace.shared.open(u) }
            done(["ok": true])
        default: queue.async { [weak self] in guard let self = self else { return }; done(self.run(r)) }
        }
    }

    // 0 not asked, 1 restricted, 2 denied, 3 full (authorized before macOS 14), 4 write only
    func access() -> String {
        switch EKEventStore.authorizationStatus(for: .event).rawValue {
        case 0: return "notDetermined"
        case 1: return "restricted"
        case 3: return "full"
        case 4: return "writeOnly"
        default: return "denied"
        }
    }

    // macOS asks once; after that the answer is whatever he chose (System Settings changes it)
    func requestAccess(_ done: @escaping (Any) -> Void) {
        let after: (Bool, Error?) -> Void = { [weak self] _, _ in done(["ok": true, "access": self?.access() ?? "denied"]) }
        if #available(macOS 14.0, *) { store.requestFullAccessToEvents(completion: after) }
        else { store.requestAccess(to: .event, completion: after) }
    }

    func run(_ r: BridgeRequest) -> Any {
        guard access() == "full" else { return ["ok": false, "code": "denied"] }
        switch r.op {
        case "calendars": return ["ok": true, "calendars": store.calendars(for: .event).map(calendarJSON)]
        case "events": return events(r)
        case "save": return save(r)
        case "remove": return remove(r)
        default: return ["ok": false, "code": "failed"]
        }
    }

    func calendarJSON(_ c: EKCalendar) -> [String: Any] {
        let kinds: [EKSourceType: String] = [.local: "local", .exchange: "exchange", .calDAV: "caldav", .mobileMe: "mobileme", .subscribed: "subscribed", .birthdays: "birthdays"]
        return ["id": c.calendarIdentifier, "title": clip(c.title, 200), "source": clip(c.source?.title, 200), "kind": c.source.flatMap { kinds[$0.sourceType] } ?? "other",
                "color": hexOf(c.color), "allowsModify": c.allowsContentModifications]
    }

    func eventJSON(_ e: EKEvent) -> [String: Any]? {
        guard let id = e.eventIdentifier, let s = e.startDate, let en = e.endDate, let cal = e.calendar else { return nil }
        var o: [String: Any] = ["eid": id, "occ": ms(e.occurrenceDate ?? s), "cal": cal.calendarIdentifier, "title": clip(e.title, 500), "start": ms(s), "end": ms(en),
                                "allDay": e.isAllDay, "rec": e.hasRecurrenceRules, "stamp": ms(e.lastModifiedDate)]
        // a title or place longer than the page takes (500, as it counts) is marked cut, and the page never writes it back (V9 re-check R1, R2)
        if let t = e.title, t.utf16.count > 500 { o["titleCut"] = true }
        if let l = e.location, !l.isEmpty { o["loc"] = clip(l, 500); if l.utf16.count > 500 { o["locCut"] = true } }
        // the page's limit (5,000, as it counts); longer notes are marked cut, and the page never writes them back (V9 review finding 2)
        if let n = e.notes, !n.isEmpty { o["notes"] = clip(n, 5000); if n.utf16.count > 5000 { o["notesCut"] = true } }
        if let u = e.url, let sc = u.scheme?.lowercased(), sc == "https" || sc == "http" { o["url"] = clip(u.absoluteString, 500) }
        if let who = e.attendees, !who.isEmpty { o["who"] = who.prefix(8).compactMap { $0.name }.map { clip($0, 120) } }
        if let g = e.attendees, !g.isEmpty { o["guests"] = true }   // even when no guest has a name (the page shows it read-only, GD-072)
        if e.status == .canceled { o["cancelled"] = true }
        return o
    }

    func events(_ r: BridgeRequest) -> Any {
        let p = store.predicateForEvents(withStart: Date(timeIntervalSince1970: r.from / 1000), end: Date(timeIntervalSince1970: r.to / 1000), calendars: nil)
        let all = store.events(matching: p)
        return ["ok": true, "events": all.prefix(BRIDGE_MAX_EVENTS).compactMap(eventJSON), "more": all.count > BRIDGE_MAX_EVENTS]
    }

    // one occurrence: the series' id and the date this occurrence was first given (a moved one keeps it)
    func occurrence(_ eid: String, _ occ: Double) -> EKEvent? {
        guard let first = store.event(withIdentifier: eid) else { return nil }
        let d = Date(timeIntervalSince1970: occ / 1000)
        if !first.hasRecurrenceRules && !first.isDetached { return first }
        let p = store.predicateForEvents(withStart: d.addingTimeInterval(-2 * 86400), end: d.addingTimeInterval(2 * 86400), calendars: [first.calendar])
        return store.events(matching: p).first { $0.eventIdentifier == eid && abs(($0.occurrenceDate ?? $0.startDate).timeIntervalSince(d)) < 1 }
    }

    // V9 review finding 2: "This and following" and "All events" reach every occurrence they cover, a detached one too, so any of them
    // with guests refuses the change. EventKit lists occurrences only by range: from the span's first occurrence to the series' end,
    // at most BRIDGE_MAX_DAYS past this occurrence (a detached occurrence with guests further out is not seen; the report says so)
    func spanGuests(_ ev: EKEvent, _ first: EKEvent?, all: Bool) -> Int {
        guard let eid = ev.eventIdentifier, let cal = ev.calendar else { return 0 }
        let here = ev.occurrenceDate ?? ev.startDate!
        let from = (all ? (first?.startDate ?? here) : here).addingTimeInterval(-2 * 86400)   // a detached one moved a little earlier
        var to = here.addingTimeInterval(BRIDGE_MAX_DAYS * 86400)
        if let end = ev.recurrenceRules?.first?.recurrenceEnd?.endDate, end < to { to = end.addingTimeInterval(2 * 86400) }
        return guestWindows(from, to).reduce(0) { n, w in
            n + store.events(matching: store.predicateForEvents(withStart: w.0, end: w.1, calendars: [cal])).filter { $0.eventIdentifier == eid }.reduce(0) { $0 + ($1.attendees?.count ?? 0) } }
    }

    func failed(_ e: Error) -> [String: Any] { return ["ok": false, "code": "failed", "msg": clip(e.localizedDescription, 200)] }

    func save(_ r: BridgeRequest) -> Any {
        var target: EKCalendar? = nil
        if let cid = r.set.cal {
            guard let c = store.calendar(withIdentifier: cid) else { return ["ok": false, "code": "gone"] }
            guard c.allowsContentModifications else { return ["ok": false, "code": "readonly"] }
            target = c
        }
        guard let eid = r.eid, let occ = r.occ else {   // a new event in the chosen calendar
            let e = EKEvent(eventStore: store)
            e.calendar = target; e.title = r.set.title
            e.isAllDay = r.set.allDay ?? false
            e.startDate = Date(timeIntervalSince1970: r.set.start! / 1000); e.endDate = Date(timeIntervalSince1970: r.set.end! / 1000)
            if let l = r.set.loc, !l.isEmpty { e.location = l }
            if let n = r.set.notes, !n.isEmpty { e.notes = n }
            do { try store.save(e, span: .thisEvent, commit: true) } catch { return failed(error) }
            return ["ok": true, "eid": e.eventIdentifier ?? "", "occ": ms(e.occurrenceDate ?? e.startDate)]
        }
        guard let ev = occurrence(eid, occ) else { return ["ok": false, "code": "gone"] }
        guard ev.calendar.allowsContentModifications else { return ["ok": false, "code": "readonly"] }
        if let no = guestRefusal(ev.attendees?.count ?? 0) { return no }
        if let st = r.stamp, abs(ms(ev.lastModifiedDate) - st) > 1 { return ["ok": false, "code": "changed"] }   // changed under him: the page reloads and shows it
        let rec = ev.hasRecurrenceRules || ev.isDetached
        // a repeating event moves to another calendar as a whole series
        let span = rec ? (target != nil && target != ev.calendar ? "all" : r.span) : "this"
        var e: EKEvent = ev, delta = 0.0, len = 0.0
        if r.set.hasTime { delta = r.set.start! / 1000 - ev.startDate.timeIntervalSince1970; len = (r.set.end! - r.set.start!) / 1000 }
        if span == "all", let first = store.event(withIdentifier: eid) { e = first }   // the whole series is saved from its first occurrence
        if let no = guestRefusal(e.attendees?.count ?? 0) { return no }
        if span != "this", let no = guestRefusal(spanGuests(ev, store.event(withIdentifier: eid), all: span == "all")) { return no }   // every occurrence the span reaches
        if let t = r.set.title { e.title = t }
        if let l = r.set.loc { e.location = l.isEmpty ? nil : l }
        if let n = r.set.notes { e.notes = n.isEmpty ? nil : n }
        if let c = target { e.calendar = c }
        if r.set.hasTime {
            e.isAllDay = r.set.allDay ?? false
            // the series keeps each occurrence's own day: it moves by what this one moved
            let start = span == "all" ? e.startDate.addingTimeInterval(delta) : Date(timeIntervalSince1970: r.set.start! / 1000)
            e.startDate = start; e.endDate = start.addingTimeInterval(len)
        }
        do { try store.save(e, span: span == "this" ? .thisEvent : .futureEvents, commit: true) } catch { return failed(error) }
        let outEid = e.eventIdentifier ?? eid, outOcc = span == "this" ? ms(e.occurrenceDate ?? e.startDate) : occ
        // the stamp the next save of this occurrence is checked against (V9 review finding 6: his own save moved it)
        let stamp = ms((occurrence(outEid, outOcc) ?? e).lastModifiedDate)
        return ["ok": true, "eid": outEid, "occ": outOcc, "span": span, "stamp": stamp]
    }

    func remove(_ r: BridgeRequest) -> Any {
        guard let eid = r.eid, let occ = r.occ, let ev = occurrence(eid, occ) else { return ["ok": false, "code": "gone"] }
        guard ev.calendar.allowsContentModifications else { return ["ok": false, "code": "readonly"] }
        if let no = guestRefusal(ev.attendees?.count ?? 0) { return no }
        if let st = r.stamp, abs(ms(ev.lastModifiedDate) - st) > 1 { return ["ok": false, "code": "changed"] }
        let rec = ev.hasRecurrenceRules || ev.isDetached
        var e: EKEvent = ev
        if rec && r.span == "all", let first = store.event(withIdentifier: eid) { e = first }
        if let no = guestRefusal(e.attendees?.count ?? 0) { return no }
        if rec && r.span != "this", let no = guestRefusal(spanGuests(ev, store.event(withIdentifier: eid), all: r.span == "all")) { return no }   // every occurrence the span reaches
        do { try store.remove(e, span: rec && r.span != "this" ? .futureEvents : .thisEvent, commit: true) } catch { return failed(error) }
        return ["ok": true]
    }
}

let OFFLINE_HTML = """
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Gena</title>
<style>
  :root{ color-scheme: light dark; }
  body{ margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
    font:16px/1.5 -apple-system, system-ui, sans-serif; background:Canvas; color:CanvasText; }
  main{ max-width:340px; padding:28px; text-align:center; }
  h1{ font-size:20px; margin:0 0 6px; }
  p{ margin:0 0 18px; opacity:.7; }
  a{ display:inline-block; padding:11px 20px; border-radius:12px; background:#9c7420; color:#fff;
    text-decoration:none; font-weight:600; }
</style>
<main><h1>Gena can’t be reached</h1>
<p>You’re offline, and this Mac has no saved copy yet. Your tasks are safe on this device — they’ll be here when Gena opens.</p>
<a href="\(APP_URL)">Try again</a></main>
"""

final class WebController: NSViewController, WKNavigationDelegate, WKUIDelegate {
    let web: WKWebView
    let calendar = CalendarBridge()

    init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // persistent localStorage across launches
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        // V6.9: the calendar bridge, in the page's own world; the handler itself refuses any other page or a frame
        cfg.userContentController.addUserScript(WKUserScript(source: BRIDGE_JS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.addScriptMessageHandler(calendar, contentWorld: .page, name: BRIDGE_NAME)
        self.web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 820), configuration: cfg)
        super.init(nibName: nil, bundle: nil)
        calendar.web = web
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        self.view = web
    }

    // Revalidate rather than trusting the HTTP cache — GitHub Pages sends max-age=600, so a plain
    // load could show a build up to ten minutes old, and a long-running window far older than that.
    private var lastLoad = Date.distantPast

    func loadApp() {
        guard let u = URL(string: APP_URL) else { return }
        web.load(URLRequest(url: u, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
        lastLoad = Date()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadApp()
        // Coming back to the app after a while is the natural moment to pick up a push. Gated on five
        // minutes so switching windows mid-sentence never reloads under you.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if Date().timeIntervalSince(self.lastLoad) > 300 { self.loadApp() }
            else { self.calendar.tell(BRIDGE_ACTIVE_JS) }   // V6.9 M7: the page re-checks calendar access
        }
    }

    @objc func reload(_ sender: Any?) { loadApp() }

    // Offline. Revalidating needs the network, so a failed load first retries from the cache — Gena is
    // local-first and the cached page is the whole app — and only then shows a page of its own instead
    // of WebKit's blank window. The page has no origin (baseURL nil), so it cannot touch Gena's storage.
    private var triedCache = false

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        guard let u = URL(string: APP_URL) else { return }
        if !triedCache {
            triedCache = true
            web.load(URLRequest(url: u, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15))
            return
        }
        triedCache = false
        web.loadHTMLString(OFFLINE_HTML, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.host == HOME_HOST { triedCache = false }
    }

    // Keep Gena inside the app; send outside links to the real browser.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // GD-075 F4: a link with `download` from Gena's own page is saved as a file; from anywhere else it is refused
        if #available(macOS 11.3, *), navigationAction.shouldPerformDownload {
            let f = navigationAction.sourceFrame, o = f.securityOrigin
            let ok = downloadAllowed(isMainFrame: f.isMainFrame, scheme: o.protocol, host: o.host, port: o.port, path: f.request.url?.path, linkScheme: navigationAction.request.url?.scheme)
            decisionHandler(ok ? .download : .cancel)
            return
        }
        if navigationAction.navigationType == .linkActivated,
           let u = navigationAction.request.url,
           let scheme = u.scheme, scheme.hasPrefix("http"),
           (u.host ?? "") != HOME_HOST {
            NSWorkspace.shared.open(u)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }

    // target="_blank" / window.open → open externally instead of a dead popup
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url { NSWorkspace.shared.open(u) }
        return nil
    }
}

// GD-075 F4: where a download goes and what the page is told (macOS 11.3+, so the app still opens on 11.0)
@available(macOS 11.3, *)
extension WebController: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { completionHandler(nil); return }
        let name = freeFileName(safeFileName(suggestedFilename)) { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
        completionHandler(dir.appendingPathComponent(name))
    }

    func downloadDidFinish(_ download: WKDownload) { calendar.tell(DOWNLOAD_SAVED_JS) }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { calendar.tell(DOWNLOAD_FAILED_JS) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var controller: WebController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = WebController()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Gena"
        window.contentViewController = controller
        window.setFrameAutosaveName("GenaMainWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func reload(_ sender: Any?) { controller?.reload(sender) }
}

func buildMenu(_ delegate: AppDelegate) -> NSMenu {
    let main = NSMenu()

    // App menu
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About Gena", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide Gena", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    let others = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    others.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit Gena", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu

    // Edit menu (makes Cmd+C/V/X/A + undo work in the web view)
    let editItem = NSMenuItem(); main.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu

    // View menu
    let viewItem = NSMenuItem(); main.addItem(viewItem)
    let viewMenu = NSMenu(title: "View")
    let reload = viewMenu.addItem(withTitle: "Reload", action: #selector(AppDelegate.reload(_:)), keyEquivalent: "r")
    reload.target = delegate
    viewItem.submenu = viewMenu

    // Window menu
    let winItem = NSMenuItem(); main.addItem(winItem)
    let winMenu = NSMenu(title: "Window")
    winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    winItem.submenu = winMenu
    NSApp.windowsMenu = winMenu

    return main
}

#if GENA_SELFCHECK
// V6.9: build.sh compiles this file a second time with -D GENA_SELFCHECK and runs it. It checks the bridge's gate and
// its request checks only: no window, no web page, no EventKit store, no calendar is touched.
func selfCheck() -> Int32 {
    var n = 0, bad: [String] = []
    func ok(_ c: Bool, _ what: String) { n += 1; if !c { bad.append(what) } }
    func parses(_ b: Any) -> Bool { return parseBridgeRequest(b).0 != nil }
    let H = "skabone.github.io"
    ok(bridgeAllowed(isMainFrame: true, scheme: "https", host: H, port: 0, path: "/gena"), "the hosted page")
    ok(bridgeAllowed(isMainFrame: true, scheme: "https", host: H, port: 0, path: "/gena/index.html"), "the hosted page, by file")
    ok(bridgeAllowed(isMainFrame: true, scheme: "https", host: H, port: 443, path: "/gena/"), "port 443 written out")
    ok(!bridgeAllowed(isMainFrame: false, scheme: "https", host: H, port: 0, path: "/gena/"), "a frame inside Gena is refused")
    ok(!bridgeAllowed(isMainFrame: true, scheme: "http", host: H, port: 0, path: "/gena/"), "plain http is refused")
    ok(!bridgeAllowed(isMainFrame: true, scheme: "https", host: "evil.github.io", port: 0, path: "/gena/"), "another github.io site is refused")
    ok(!bridgeAllowed(isMainFrame: true, scheme: "https", host: "skabone.github.io.evil.test", port: 0, path: "/gena/"), "a look-alike host is refused")
    ok(!bridgeAllowed(isMainFrame: true, scheme: "https", host: H, port: 8443, path: "/gena/"), "another port is refused")
    ok(!bridgeAllowed(isMainFrame: true, scheme: "https", host: H, port: 0, path: "/genax/"), "another path on the host is refused")
    ok(!bridgeAllowed(isMainFrame: true, scheme: "https", host: H, port: 0, path: "/other/"), "another project on the host is refused")
    ok(!bridgeAllowed(isMainFrame: true, scheme: "https", host: H, port: 0, path: nil), "no path is refused")
    ok(!bridgeAllowed(isMainFrame: true, scheme: nil, host: nil, port: 0, path: nil), "the offline page (no origin) is refused")
    ok(parses(["op": "status"]) && parses(["op": "calendars", "args": [String: Any]()]), "status and calendars")
    ok(!parses(["op": "eval"]) && !parses(["op": "status", "x": 1]) && !parses("status") && !parses(["op": "status", "args": ["a": 1]]), "an unknown op, an extra key, a bare string, stray arguments")
    let t0 = 1_790_000_000_000.0
    ok(parses(["op": "events", "args": ["from": t0, "to": t0 + 30 * DAY_MS]]), "a month of events")
    ok(!parses(["op": "events", "args": ["from": t0, "to": t0 + 500 * DAY_MS]]), "more than 420 days is refused")
    ok(!parses(["op": "events", "args": ["from": t0, "to": t0 - 1]]) && !parses(["op": "events", "args": ["from": "1", "to": t0]]) && !parses(["op": "events", "args": ["from": true, "to": t0]]), "a backwards range, a string, a boolean")
    ok(!parses(["op": "events", "args": ["from": Double.nan, "to": t0]]) && !parses(["op": "events", "args": ["from": -5.0, "to": t0]]), "not a number, before 1970")
    let time: [String: Any] = ["allDay": false, "start": t0, "end": t0 + 3_600_000]
    ok(parses(["op": "save", "args": ["event": ["eid": "A:B", "occ": t0, "span": "this", "stamp": t0, "set": ["title": "Lunch"]]]]), "a title change")
    ok(parses(["op": "save", "args": ["event": ["eid": "A:B", "occ": t0, "span": "future", "set": time]]]), "a time change, this and following")
    ok(!parses(["op": "save", "args": ["event": ["eid": "A:B", "occ": t0, "set": ["start": t0, "end": t0 + 1]]]]), "a time without all-day is refused")
    ok(!parses(["op": "save", "args": ["event": ["eid": "A:B", "occ": t0, "set": ["allDay": 1, "start": t0, "end": t0 + 1]]]]), "all-day must be a boolean")
    ok(!parses(["op": "save", "args": ["event": ["eid": "A:B", "occ": t0, "span": "every", "set": ["title": "x"]]]]), "an unknown span is refused")
    ok(!parses(["op": "save", "args": ["event": ["eid": "A:B", "occ": t0, "set": ["title": "x", "alarms": [1]]]]]), "alerts stay in the Calendar app (an unknown field is refused)")
    ok(!parses(["op": "save", "args": ["event": ["eid": "A:B", "occ": t0, "set": ["title": "   "]]]]) && !parses(["op": "save", "args": ["event": ["eid": "A:B", "occ": t0, "set": ["title": String(repeating: "x", count: 501)]]]]), "an empty or very long title")
    ok(!parses(["op": "save", "args": ["event": ["eid": "A:B", "set": ["title": "x"]]]]) && !parses(["op": "save", "args": ["event": ["eid": "", "occ": t0, "set": ["title": "x"]]]]), "an id with no occurrence, an empty id")
    var made = time; made["title"] = "New"; made["cal"] = "CAL-1"
    ok(parses(["op": "save", "args": ["event": ["set": made]]]), "a new event: calendar, title and time")
    made["cal"] = nil
    ok(!parses(["op": "save", "args": ["event": ["set": made]]]), "a new event with no calendar is refused")
    ok(parses(["op": "remove", "args": ["eid": "A:B", "occ": t0, "span": "all"]]) && !parses(["op": "remove", "args": ["eid": "A:B"]]) && !parses(["op": "remove", "args": ["eid": "A:B", "occ": t0, "x": 1]]), "remove: an occurrence, a missing date, an extra key")
    ok(guestRefusal(1)?["code"] as? String == "guests" && guestRefusal(3)?["ok"] as? Bool == false && guestRefusal(0) == nil, "a meeting with guests is refused on save and remove (GD-072)")
    let gw = guestWindows(Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 1000 * 86400)), day0 = Date(timeIntervalSince1970: 0)
    ok(gw.count == 3 && gw.first?.0 == day0 && gw.last?.1 == Date(timeIntervalSince1970: 1000 * 86400) && zip(gw, gw.dropFirst()).allSatisfy { $0.1 == $1.0 } && gw.allSatisfy { $0.1.timeIntervalSince($0.0) <= BRIDGE_MAX_DAYS * 86400 } && guestWindows(day0, day0).isEmpty, "a span with guests anywhere in it is read whole, in back-to-back pieces (V9 review finding 2)")
    ok(BRIDGE_JS.contains("location.hostname !== \"skabone.github.io\"") && BRIDGE_JS.contains("window.top !== window"), "the page script checks the origin and the frame too")
    let NP = "window.dispatchEvent(new CustomEvent('gena-native',{detail:'"
    ok([BRIDGE_CHANGED_JS, BRIDGE_ACTIVE_JS, DOWNLOAD_SAVED_JS, DOWNLOAD_FAILED_JS].allSatisfy { $0.hasPrefix(NP) && $0.hasSuffix("'}))") && $0.dropFirst(NP.count).dropLast(4).allSatisfy { $0.isLetter } }, "the only lines run in the page are the four fixed notices (calendars changed, back to the front, a download saved or not)")
    // GD-075 F4: downloads
    ok(downloadAllowed(isMainFrame: true, scheme: "https", host: H, port: 0, path: "/gena/", linkScheme: "blob") && downloadAllowed(isMainFrame: true, scheme: "https", host: H, port: 0, path: "/gena/", linkScheme: "data"), "a download: Gena's own page, a blob or data link")
    ok(!downloadAllowed(isMainFrame: false, scheme: "https", host: H, port: 0, path: "/gena/", linkScheme: "blob") && !downloadAllowed(isMainFrame: true, scheme: "https", host: "evil.github.io", port: 0, path: "/gena/", linkScheme: "blob") && !downloadAllowed(isMainFrame: true, scheme: nil, host: nil, port: 0, path: nil, linkScheme: "blob"), "a download from a frame, another site or the offline page is refused")
    ok(!downloadAllowed(isMainFrame: true, scheme: "https", host: H, port: 0, path: "/gena/", linkScheme: "https") && !downloadAllowed(isMainFrame: true, scheme: "https", host: H, port: 0, path: "/gena/", linkScheme: "file") && !downloadAllowed(isMainFrame: true, scheme: "https", host: H, port: 0, path: "/gena/", linkScheme: nil), "a download of a web, file or missing link is refused (only a file the page made)")
    ok(safeFileName("daybook-backup-2026-10-21.json") == "daybook-backup-2026-10-21.json" && safeFileName("../../.ssh/config") == "config" && safeFileName("a/b\\c:d.ics") == "d.ics" && safeFileName(".hidden") == "hidden" && safeFileName("  ") == "Gena download" && safeFileName(String(repeating: "x", count: 300)).count == 120 && safeFileName("tab\tname.csv") == "tabname.csv", "a suggested name becomes one plain name: no folders, no hidden or empty name, no control characters, at most 120 characters")
    var have: Set<String> = ["daybook-2026-10-21.ics", "daybook-2026-10-21 (1).ics", "notes"]
    ok(freeFileName("free.json") { have.contains($0) } == "free.json" && freeFileName("daybook-2026-10-21.ics") { have.contains($0) } == "daybook-2026-10-21 (2).ics" && freeFileName("notes") { have.contains($0) } == "notes (1)", "never over a file already there: the name, else name (1), name (2) before the extension")
    have.insert("notes (1)"); ok(freeFileName("notes") { have.contains($0) } == "notes (2)", "…counting on past the ones taken")
    // V25 finding 5: a name of many-byte characters is cut on UTF-8 bytes, between whole characters, keeping its extension
    let fam = "\u{1F1EA}\u{1F1F9}", wide = safeFileName(String(repeating: fam, count: 40) + ".csv"), acc = safeFileName(String(repeating: "\u{E9}", count: 150) + ".json")
    ok(wide.utf8.count <= NAME_MAX_BYTES && wide.hasSuffix(".csv") && String(wide.dropLast(4)) == String(repeating: fam, count: wide.count - 4) && wide.count > 4 && acc.utf8.count <= NAME_MAX_BYTES && acc.hasSuffix(".json") && acc.count > 50 && safeFileName(String(repeating: "x", count: 300) + ".json").hasSuffix(".json") && safeFileName(String(repeating: "x", count: 300) + ".json").count == 120, "a long name is cut on its UTF-8 bytes (at most \(NAME_MAX_BYTES)) and its characters, whole characters only, and keeps its extension")
    let big = freeFileName(wide) { _ in true }, big1 = freeFileName(acc) { $0 == acc }
    ok(big.utf8.count < 255 && big.hasSuffix(".csv") && big1.utf8.count < 255 && big1.hasSuffix(" (1).json"), "…so with \" (n)\" or the last-resort UUID it stays under APFS's 255 bytes")
    print(bad.isEmpty ? "✓ bridge self-check: \(n) checks" : "✗ bridge self-check: \(bad.count) of \(n) failed: " + bad.joined(separator: "; "))
    return bad.isEmpty ? 0 : 1
}
exit(selfCheck())
#else
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.mainMenu = buildMenu(delegate)
app.run()
#endif
