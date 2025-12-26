load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

load(
    "@build_bazel_rules_apple//apple:resources.bzl",
    "apple_resource_bundle",
    "apple_resource_group",
)
load(
    "//build-system/bazel-utils:plist_fragment.bzl",
    "plist_fragment",
)

filegroup(
    name = "LiquidGlassMetalSources",
    srcs = glob([
        "Shaders/**/*.metal",
    ]),
    visibility = ["//visibility:public"],
)

plist_fragment(
    name = "LiquidGlassMetalSourcesBundleInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleIdentifier</key>
    <string>org.telegram.LiquidGlassMetalSources</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>LiquidGlassUI</string>
    """,
)

apple_resource_bundle(
    name = "LiquidGlassMetalSourcesBundle",
    infoplists = [
        ":LiquidGlassMetalSourcesBundleInfoPlist",
    ],
    resources = [
        ":LiquidGlassMetalSources",
    ],
)

swift_library(
    name = "LiquidGlassUI",
    module_name = "LiquidGlassUI",
    srcs = glob(
        [
            "Sources/**/*.swift",
        ],
        exclude = [
            "Sources/LiquidGlass/LiquidChat/TelegramStubs.swift",
            "Sources/LiquidGlass/LiquidChat/LiquidChatSettingsView.swift",
        ],
    ),
    copts = [
        "-warnings-as-errors",
    ],
    data = [
        ":LiquidGlassMetalSourcesBundle",
    ],
    deps = [
        "//Telegram:PresentationStrings",
        "//submodules/AccountContext",
        "//submodules/ChatInterfaceState",
        "//submodules/ChatPresentationInterfaceState",
        "//submodules/ComponentFlow",
        "//submodules/Display",
        "//submodules/TelegramPresentationData",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
