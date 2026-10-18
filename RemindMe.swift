import Combine
import SwiftUI
import UserNotifications

// MARK: - Model

struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var due: Date?
    var done = false
    var created = Date()
}

// Dates are shown in English (24-hour time) to match the rest of the app.
let appLocale = Locale(identifier: "en_GB")

/// Ready-made times offered in the composer, the time picker and the snooze menu.
enum QuickTime: CaseIterable, Identifiable {
    case in15, in1h, in3h, evening, tomorrowMorning, weekend, nextWeek

    var id: Self { self }

    var icon: String {
        switch self {
        case .in15: return "timer"
        case .in1h: return "clock"
        case .in3h: return "clock.badge"
        case .evening: return "moon.stars"
        case .tomorrowMorning: return "sunrise"
        case .weekend: return "sun.max"
        case .nextWeek: return "calendar"
        }
    }

    func label(now: Date = Date()) -> String {
        switch self {
        case .in15: return "In 15 minutes"
        case .in1h: return "In 1 hour"
        case .in3h: return "In 3 hours"
        case .evening: return Calendar.current.isDateInToday(date(from: now)) ? "This evening" : "Tomorrow evening"
        case .tomorrowMorning: return "Tomorrow morning"
        case .weekend: return "This weekend"
        case .nextWeek: return "Next Monday"
        }
    }

    /// Shorter name for the chips under the text field.
    func shortLabel(now: Date = Date()) -> String {
        switch self {
        case .in15: return "15 min"
        case .in1h: return "1 hour"
        case .in3h: return "3 hours"
        case .evening: return "Evening"
        case .tomorrowMorning: return "Tomorrow"
        case .weekend: return "Weekend"
        case .nextWeek: return "Next week"
        }
    }

    func date(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        func at(_ hour: Int, daysAhead: Int) -> Date {
            let day = cal.date(byAdding: .day, value: daysAhead, to: now)!
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        }
        func later(_ seconds: TimeInterval) -> Date {
            let d = now.addingTimeInterval(seconds)
            return cal.date(bySetting: .second, value: 0, of: d) ?? d
        }
        let weekday = cal.component(.weekday, from: now) // 1 = Sunday ... 7 = Saturday
        switch self {
        case .in15: return later(15 * 60)
        case .in1h: return later(3600)
        case .in3h: return later(3 * 3600)
        case .evening:
            for candidate in [at(18, daysAhead: 0), at(20, daysAhead: 0)] where candidate > now {
                return candidate
            }
            return at(18, daysAhead: 1)
        case .tomorrowMorning: return at(9, daysAhead: 1)
        case .weekend:
            let saturday = at(10, daysAhead: (7 - weekday) % 7)
            return saturday > now ? saturday : at(10, daysAhead: 1) // Saturday afternoon: Sunday
        case .nextWeek:
            // On Sunday, tomorrow is already Monday, so skip to the one after.
            let ahead = (9 - weekday) % 7
            return at(9, daysAhead: ahead <= 1 ? ahead + 7 : ahead)
        }
    }

    /// The actual time it lands on, e.g. "18:00" or "Sat 10:00".
    func detail(now: Date = Date()) -> String {
        let d = date(from: now)
        let time = timeString(d)
        return Calendar.current.isDateInToday(d)
            ? time
            : "\(d.formatted(.dateTime.weekday(.abbreviated).locale(appLocale))) \(time)"
    }
}

func timeString(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(appLocale))
}

func relative(_ date: Date) -> String {
    date.formatted(Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide, locale: appLocale))
}

func describe(_ date: Date) -> String {
    let cal = Calendar.current
    let time = timeString(date)
    if cal.isDateInToday(date) { return "Today, \(time)" }
    if cal.isDateInTomorrow(date) { return "Tomorrow, \(time)" }
    if cal.isDateInYesterday(date) { return "Yesterday, \(time)" }
    let sameYear = cal.isDate(date, equalTo: Date(), toGranularity: .year)
    let day = sameYear
        ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(appLocale))
        : date.formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale))
    return "\(day), \(time)"
}

// MARK: - Understanding times typed into the text

struct DetectedTime: Equatable {
    let date: Date
    let range: NSRange

    /// The text with the time phrase taken out ("call mom tomorrow at 6pm" -> "call mom").
    func strip(from text: String) -> String {
        var rest = (text as NSString).replacingCharacters(in: range, with: " ")
        rest = rest.replacingOccurrences(of: #"\s+(at|on|by|in)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        rest = rest.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return rest.isEmpty ? text : rest
    }
}

private let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
private let relativePattern = try! NSRegularExpression(
    pattern: #"\b(?:in|after)\s+(\d+|an?|half an)\s*(m|mins?|minutes?|h|hrs?|hours?|days?|weeks?)\b"#,
    options: .caseInsensitive)

/// Finds phrases like "tomorrow at 6pm", "friday", "17:30" or "in 20 minutes".
func detectTime(in text: String, now: Date = Date()) -> DetectedTime? {
    let ns = text as NSString
    let all = NSRange(location: 0, length: ns.length)
    let cal = Calendar.current

    if let m = relativePattern.firstMatch(in: text, range: all) {
        let amountText = ns.substring(with: m.range(at: 1)).lowercased()
        let unit = ns.substring(with: m.range(at: 2)).lowercased()
        var minutes: Double = amountText == "half an" ? 0.5 : amountText.hasPrefix("a") ? 1 : Double(amountText) ?? 1
        if unit.hasPrefix("h") { minutes *= 60 }
        else if unit.hasPrefix("d") { minutes *= 60 * 24 }
        else if unit.hasPrefix("w") { minutes *= 60 * 24 * 7 }
        let d = now.addingTimeInterval(minutes * 60)
        return DetectedTime(date: cal.date(bySetting: .second, value: 0, of: d) ?? d, range: m.range)
    }

    guard let m = dateDetector?.firstMatch(in: text, range: all), var date = m.date else { return nil }
    let phrase = ns.substring(with: m.range).lowercased()
    let mentionsTime = phrase.rangeOfCharacter(from: .decimalDigits) != nil
        || ["noon", "midnight", "morning", "afternoon", "evening", "tonight", "night"].contains { phrase.contains($0) }
    // A day without a time ("friday") means the morning, not midday.
    if !mentionsTime {
        date = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }
    // A time that already passed today ("at 9am" in the evening) means tomorrow.
    if date <= now, cal.isDateInToday(date) {
        date = cal.date(byAdding: .day, value: 1, to: date) ?? date
    }
    return DetectedTime(date: date, range: m.range)
}

/// How pressing a reminder is, which decides its color.
enum Urgency {
    case overdue, today, later, someday, done

    init(_ r: Reminder, now: Date) {
        if r.done { self = .done }
        else if let due = r.due {
            if due <= now { self = .overdue }
            else if Calendar.current.isDateInToday(due) { self = .today }
            else { self = .later }
        } else { self = .someday }
    }

    var color: Color {
        switch self {
        case .overdue: return .red
        case .today: return .orange
        case .later: return .blue
        case .someday: return .purple
        case .done: return .green
        }
    }
}

// MARK: - Storage and notifications

@MainActor
final class Store: ObservableObject {
    @Published var reminders: [Reminder] = [] {
        didSet {
            save()
            scheduleNotifications()
        }
    }

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Remind Me", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("reminders.json")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: self.fileURL),
           let saved = try? decoder.decode([Reminder].self, from: data) {
            reminders = saved
        }
        scheduleNotifications()
    }

    func add(_ text: String, due: Date?) {
        reminders.append(Reminder(text: text, due: due))
    }

    func toggle(_ r: Reminder) {
        update(r) { $0.done.toggle() }
    }

    func setDue(_ r: Reminder, _ date: Date?) {
        update(r) { $0.due = date }
    }

    func delete(_ r: Reminder) {
        reminders.removeAll { $0.id == r.id }
    }

    func clearDone() {
        reminders.removeAll(where: \.done)
    }

    private func update(_ r: Reminder, _ change: (inout Reminder) -> Void) {
        guard let i = reminders.firstIndex(where: { $0.id == r.id }) else { return }
        change(&reminders[i])
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(reminders).write(to: fileURL, options: .atomic)
    }

    // macOS delivers these itself, so reminders still fire after the app is quit.
    private func scheduleNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        for r in reminders where !r.done {
            guard let due = r.due, due > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Reminder"
            content.body = r.text
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: r.id.uuidString, content: content, trigger: trigger))
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // Show the banner even when the app is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

#if !SNAPSHOT
@main
struct RemindMeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        Window("Remind Me", id: "main") {
            ContentView().environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 540, height: 700)
    }
}
#endif

// MARK: - Views

let cardBackground = Color(nsColor: .controlBackgroundColor)

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var text: String
    @State private var manualDue: Date?
    @State private var chosen: QuickTime?
    @State private var ignoreDetected = false
    @State private var showingPicker = false
    @State private var showDone = false
    @State private var now = Date()
    @FocusState private var typing: Bool

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(text: String = "") {
        _text = State(initialValue: text)
    }

    /// A time found in what you typed, unless you picked one yourself.
    private var detected: DetectedTime? {
        manualDue != nil || ignoreDetected ? nil : detectTime(in: text, now: now)
    }

    private var due: Date? { manualDue ?? detected?.date }

    var body: some View {
        let open = store.reminders.filter { !$0.done }
        let byDue: (Reminder, Reminder) -> Bool = { $0.due! < $1.due! }
        let overdue = open.filter { Urgency($0, now: now) == .overdue }.sorted(by: byDue)
        let upcoming = open.filter { $0.due.map { $0 > now } ?? false }.sorted(by: byDue)
        let noDate = open.filter { $0.due == nil }.sorted { $0.created > $1.created }
        let done = store.reminders.filter(\.done).sorted { $0.created > $1.created }

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(overdue: overdue.count, upcoming: upcoming.count)
                composer

                if open.isEmpty {
                    emptyState
                } else {
                    section("Overdue", icon: "exclamationmark.circle.fill", color: .red, items: overdue)
                    section("Upcoming", icon: "bell.fill", color: .orange, items: upcoming)
                    section("No date", icon: "tray.fill", color: .purple, items: noDate)
                }

                if !done.isEmpty { doneSection(done) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 24)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.reminders)
        }
        .scrollIndicators(.never)
        .background(background)
        .frame(minWidth: 500, minHeight: 520)
        .tint(.orange)
        .environment(\.locale, appLocale)
        .environment(\.now, now)
        .onReceive(tick) { now = $0 }
        .onAppear { typing = true }
    }

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [Color.orange.opacity(0.14), Color.pink.opacity(0.05), .clear],
                           startPoint: .topLeading, endPoint: .center)
        }
        .ignoresSafeArea()
    }

    private func header(overdue: Int, upcoming: Int) -> some View {
        let hour = Calendar.current.component(.hour, from: now)
        let greeting = hour < 5 ? "Good night" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"

        return VStack(alignment: .leading, spacing: 4) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(appLocale)).uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text(greeting)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Group {
                if overdue > 0 {
                    Text("\(overdue) overdue").foregroundStyle(.red).bold() + Text(upcoming > 0 ? " · \(upcoming) coming up" : "")
                } else if upcoming > 0 {
                    Text("\(upcoming) coming up")
                } else {
                    Text("You're all caught up")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                TextField("What do you need to remember?", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($typing)
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(canAdd ? Color.orange : Color.secondary.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)
                .help("Add reminder (Return)")
            }

            HStack(spacing: 6) {
                ForEach([QuickTime.in1h, .evening, .tomorrowMorning, .weekend]) { q in
                    Chip(title: q.shortLabel(now: now), icon: q.icon, selected: chosen == q) {
                        if chosen == q {
                            chosen = nil
                            manualDue = nil
                        } else {
                            chosen = q
                            manualDue = q.date(from: now)
                        }
                    }
                    .help("\(q.label(now: now)) · \(q.detail(now: now))")
                }
                Chip(title: "Pick time", icon: "calendar.badge.clock",
                     selected: manualDue != nil && chosen == nil) {
                    showingPicker = true
                }
                .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                    WhenPicker(date: Binding(get: { due }, set: { newValue in
                        chosen = nil
                        manualDue = newValue
                        if newValue == nil { ignoreDetected = true }
                    }), close: { showingPicker = false })
                    .environment(\.now, now)
                }
            }

            if let due {
                HStack(spacing: 6) {
                    Button { showingPicker = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: detected != nil ? "sparkles" : "bell.badge.fill")
                            Text("\(describe(due)) · \(relative(due))").fontWeight(.medium)
                            if detected != nil {
                                Text("from your text").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Change the time")

                    Button {
                        if detected != nil { ignoreDetected = true }
                        manualDue = nil
                        chosen = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("No time")
                }
                .font(.caption)
                .foregroundStyle(due <= now ? Color.red : Color.orange)
                .transition(.opacity)
            } else if !text.isEmpty {
                Text("Tip: type a time like “tomorrow at 6pm” or “in 20 minutes”")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(typing ? Color.orange.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.15), value: due)
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty { ignoreDetected = false }
        }
    }

    private var canAdd: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.add(detected?.strip(from: trimmed) ?? trimmed, due: due)
        text = ""
        manualDue = nil
        chosen = nil
        ignoreDetected = false
        typing = true
    }

    // MARK: List

    @ViewBuilder
    private func section(_ title: String, icon: String, color: Color, items: [Reminder]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: title, icon: icon, color: color, count: items.count)
                ForEach(items) { r in
                    ReminderRow(reminder: r)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .opacity.combined(with: .scale(scale: 0.95))))
                }
            }
        }
    }

    private func doneSection(_ done: [Reminder]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showDone.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        SectionHeader(title: "Done", icon: "checkmark.circle.fill", color: .green, count: done.count)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showDone ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if showDone {
                    Button("Clear all") { store.clearDone() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            if showDone {
                ForEach(done) { ReminderRow(reminder: $0) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.orange.opacity(0.25), .pink.opacity(0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)
            }
            Text("Nothing to remember")
                .font(.title3.weight(.semibold))
            Text("Write down anything you don't want to forget.\nYou'll get a notification when it's time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

extension EnvironmentValues {
    /// The current time, refreshed every 30 seconds so "in 5 minutes" labels stay right.
    @Entry var now = Date()
}

// MARK: Time picker

struct WhenPicker: View {
    @Binding var date: Date?
    let close: () -> Void
    @Environment(\.now) private var now
    @State private var draft: Date

    private static let times = [(8, 0), (9, 0), (12, 0), (15, 0), (18, 0), (20, 0), (21, 0)]

    init(date: Binding<Date?>, close: @escaping () -> Void) {
        _date = date
        self.close = close
        // Start from the current choice, or the next full hour.
        let cal = Calendar.current
        let nextHour = cal.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date()
        _draft = State(initialValue: date.wrappedValue ?? nextHour)
    }

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: today)! }

        VStack(alignment: .leading, spacing: 14) {
            Text("Remind me…").font(.headline)

            VStack(spacing: 2) {
                ForEach(QuickTime.allCases) { q in
                    QuickRow(quick: q, now: now) {
                        date = q.date(from: now)
                        close()
                    }
                }
            }

            Divider()

            Text("Or choose a day and time").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let offset = cal.dateComponents([.day], from: today, to: day).day ?? 0
                    let label = offset == 0 ? "Today" : offset == 1 ? "Tomorrow"
                        : day.formatted(.dateTime.weekday(.abbreviated).day().locale(appLocale))
                    Chip(title: label, selected: cal.isDate(draft, inSameDayAs: day), fill: true) {
                        setDay(day)
                    }
                }
                DatePicker("", selection: Binding(get: { draft }, set: { setDay($0) }),
                           in: today..., displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .controlSize(.small)
                    .help("Another day")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Self.times, id: \.0) { h, m in
                    let comps = cal.dateComponents([.hour, .minute], from: draft)
                    Chip(title: String(format: "%02d:%02d", h, m),
                         selected: comps.hour == h && comps.minute == m, fill: true) {
                        setTime(h, m)
                    }
                }
                DatePicker("", selection: $draft, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
                    .controlSize(.small)
                    .help("Exact time")
            }

            HStack(spacing: 6) {
                Image(systemName: draft <= now ? "exclamationmark.triangle.fill" : "bell.fill")
                Text(draft <= now ? "That time has already passed" : "\(describe(draft)) · \(relative(draft))")
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(draft <= now ? Color.red : Color.orange)

            HStack {
                if date != nil {
                    Button("No time", role: .destructive) {
                        date = nil
                        close()
                    }
                }
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Set") {
                    date = draft
                    close()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft <= now)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private func setDay(_ day: Date) {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: draft)
        draft = cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    private func setTime(_ hour: Int, _ minute: Int) {
        draft = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: draft) ?? draft
    }
}

struct QuickRow: View {
    let quick: QuickTime
    let now: Date
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: quick.icon)
                    .frame(width: 18)
                    .foregroundStyle(.orange)
                Text(quick.label(now: now))
                Spacer()
                Text(quick.detail(now: now))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.orange.opacity(hovering ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The snooze options, shared by the hover button and the right-click menu.
struct SnoozeOptions: View {
    @EnvironmentObject private var store: Store
    @Environment(\.now) private var now
    let reminder: Reminder

    var body: some View {
        ForEach(QuickTime.allCases) { q in
            Button("\(q.label(now: now))  ·  \(q.detail(now: now))") {
                store.setDue(reminder, q.date(from: now))
            }
        }
    }
}

// MARK: Pieces

struct Chip: View {
    let title: String?
    var icon: String? = nil
    let selected: Bool
    var fill = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                if let title { Text(title) }
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: fill ? .infinity : nil)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.8))
            .background(Capsule().fill(selected ? Color.orange
                                       : Color.primary.opacity(hovering ? 0.10 : 0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(Capsule().fill(color.opacity(0.15)))
                .foregroundStyle(color)
        }
        .padding(.leading, 4)
    }
}

struct ReminderRow: View {
    @EnvironmentObject private var store: Store
    @Environment(\.now) private var now
    let reminder: Reminder
    @State private var hovering = false
    @State private var showingPicker = false

    var body: some View {
        let urgency = Urgency(reminder, now: now)

        HStack(alignment: .center, spacing: 12) {
            Button {
                store.toggle(reminder)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(reminder.done ? Color.green : urgency.color.opacity(0.7), lineWidth: 2)
                        .background(Circle().fill(reminder.done ? Color.green : .clear))
                        .frame(width: 22, height: 22)
                    if reminder.done || hovering {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(reminder.done ? Color.white : urgency.color)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(reminder.done ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.text)
                    .font(.system(size: 14))
                    .strikethrough(reminder.done, color: .secondary)
                    .foregroundStyle(reminder.done ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let due = reminder.due {
                    Button { showingPicker = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: urgency == .overdue ? "exclamationmark.circle.fill" : "clock")
                            Text(describe(due))
                            if !reminder.done {
                                Text("·")
                                Text(relative(due))
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(reminder.done ? Color.secondary : urgency.color)
                    }
                    .buttonStyle(.plain)
                    .disabled(reminder.done)
                    .help("Change the time")
                }
            }

            Spacer(minLength: 8)

            if hovering && !reminder.done {
                HStack(spacing: 4) {
                    Menu {
                        Text("Remind me again…")
                        SnoozeOptions(reminder: reminder)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .frame(width: 26, height: 26)
                    .help("Snooze")

                    RowAction(icon: reminder.due == nil ? "calendar.badge.plus" : "calendar",
                              help: reminder.due == nil ? "Add a time" : "Change the time") {
                        showingPicker = true
                    }
                    RowAction(icon: "trash", help: "Delete", tint: .red) {
                        store.delete(reminder)
                    }
                }
                .transition(.opacity)
            } else if hovering {
                RowAction(icon: "trash", help: "Delete", tint: .red) {
                    store.delete(reminder)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackground)
                .overlay(alignment: .leading) {
                    // Colored edge showing how urgent it is.
                    UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, style: .continuous)
                        .fill(urgency.color.opacity(reminder.done ? 0.3 : 0.9))
                        .frame(width: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .shadow(color: .black.opacity(hovering ? 0.10 : 0.04), radius: hovering ? 10 : 4, y: hovering ? 4 : 1)
        .opacity(reminder.done ? 0.7 : 1)
        .scaleEffect(hovering ? 1.005 : 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            WhenPicker(date: Binding(get: { reminder.due }, set: { store.setDue(reminder, $0) }),
                       close: { showingPicker = false })
                .environment(\.now, now)
        }
        .contextMenu {
            if !reminder.done {
                Menu("Remind me again") { SnoozeOptions(reminder: reminder) }
                Button(reminder.due == nil ? "Add a time…" : "Change time…") { showingPicker = true }
                if reminder.due != nil {
                    Button("Remove time") { store.setDue(reminder, nil) }
                }
                Divider()
            }
            Button(reminder.done ? "Mark as not done" : "Mark as done") { store.toggle(reminder) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(reminder) }
        }
    }
}

struct RowAction: View {
    let icon: String
    let help: String
    var tint: Color = .primary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? tint : Color.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
