load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AstraGramUI",
    module_name = "AstraGramUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/BuildConfig:BuildConfig",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/AccountContext:AccountContext",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/UndoUI:UndoUI",
        "//submodules/Pasteboard:Pasteboard",
        "//submodules/AppBundle:AppBundle",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/TelegramUI/Components/Gifts/GiftItemComponent:GiftItemComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
