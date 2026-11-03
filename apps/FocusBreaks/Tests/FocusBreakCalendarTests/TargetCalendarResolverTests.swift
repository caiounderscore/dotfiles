import FocusBreakCalendar
import Testing

struct TargetCalendarResolverTests {
    @Test("resolves only the explicitly saved writable calendar")
    func resolvesSavedCalendar() throws {
        let calendars = [
            CalendarDescriptor(
                identifier: "academic",
                title: "Academic",
                sourceTitle: "Fastmail",
                isWritable: true
            ),
            CalendarDescriptor(
                identifier: "work-1",
                title: "Focus & Breaks",
                sourceTitle: "caio@example.com",
                isWritable: true
            ),
        ]

        let resolved = try TargetCalendarResolver.resolve(
            savedIdentifier: "work-1",
            calendars: calendars
        )

        #expect(resolved.identifier == "work-1")
        #expect(resolved.sourceTitle == "caio@example.com")
    }

    @Test("does not fall back by name when the saved calendar is unavailable")
    func rejectsNameFallback() {
        let duplicates = [
            CalendarDescriptor(
                identifier: "work-2",
                title: "Focus & Breaks",
                sourceTitle: "Fastmail",
                isWritable: true
            ),
            CalendarDescriptor(
                identifier: "work-3",
                title: "Focus & Breaks",
                sourceTitle: "Other",
                isWritable: true
            ),
        ]

        #expect(throws: TargetCalendarResolutionError.savedCalendarUnavailable) {
            try TargetCalendarResolver.resolve(
                savedIdentifier: "work-1",
                calendars: duplicates
            )
        }
    }
}
