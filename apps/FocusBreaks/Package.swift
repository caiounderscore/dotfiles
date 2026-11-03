// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "FocusBreaks",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "FocusBreakCore", targets: ["FocusBreakCore"]),
        .library(name: "FocusBreakCalendar", targets: ["FocusBreakCalendar"]),
        .library(name: "FocusBreakUI", targets: ["FocusBreakUI"]),
        .executable(name: "FocusBreaks", targets: ["FocusBreaks"]),
        .executable(name: "focusctl", targets: ["focusctl"]),
    ],
    targets: [
        .target(name: "FocusBreakCore"),
        .target(
            name: "FocusBreakCalendar",
            dependencies: ["FocusBreakCore"]
        ),
        .target(
            name: "FocusBreakUI",
            dependencies: ["FocusBreakCalendar", "FocusBreakCore"]
        ),
        .executableTarget(
            name: "FocusBreaks",
            dependencies: ["FocusBreakCalendar", "FocusBreakCore", "FocusBreakUI"]
        ),
        .executableTarget(
            name: "focusctl",
            dependencies: ["FocusBreakCore"]
        ),
        .testTarget(
            name: "FocusBreakCoreTests",
            dependencies: ["FocusBreakCore"]
        ),
        .testTarget(
            name: "FocusBreakCalendarTests",
            dependencies: ["FocusBreakCalendar", "FocusBreakCore"]
        ),
        .testTarget(
            name: "FocusBreakUITests",
            dependencies: ["FocusBreakCalendar", "FocusBreakCore", "FocusBreakUI"]
        ),
    ]
)
