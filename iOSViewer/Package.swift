// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "iOSViewer",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "iOSViewerKit", targets: ["iOSViewerKit"]),
        .executable(name: "iOSViewerApp", targets: ["iOSViewerApp"]),
        .executable(name: "iOSViewerScaffold", targets: ["iOSViewerScaffold"])
    ],
    targets: [
        .target(
            name: "CG722",
            path: "Sources/CG722",
            exclude: ["LICENSE", "WEBRTC_LICENSE", "provenance.json", "g722_enc_dec.h"],
            sources: ["g722_decode.c", "MacViewerG722.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("include")]
        ),
        .target(
            name: "CZstd",
            path: "Sources/CZstd",
            exclude: ["LICENSE", "COPYING", "provenance.json"],
            sources: [
                "lib/common/debug.c", "lib/common/entropy_common.c",
                "lib/common/error_private.c", "lib/common/fse_decompress.c",
                "lib/common/pool.c", "lib/common/threading.c",
                "lib/common/xxhash.c", "lib/common/zstd_common.c",
                "lib/compress/fse_compress.c", "lib/compress/hist.c",
                "lib/compress/huf_compress.c", "lib/compress/zstd_compress.c",
                "lib/compress/zstd_compress_literals.c", "lib/compress/zstd_compress_sequences.c",
                "lib/compress/zstd_compress_superblock.c", "lib/compress/zstd_double_fast.c",
                "lib/compress/zstd_fast.c", "lib/compress/zstd_lazy.c",
                "lib/compress/zstd_ldm.c", "lib/compress/zstd_opt.c",
                "lib/compress/zstd_preSplit.c", "lib/compress/zstdmt_compress.c",
                "lib/decompress/huf_decompress.c", "lib/decompress/zstd_ddict.c",
                "lib/decompress/zstd_decompress.c", "lib/decompress/zstd_decompress_block.c",
                "lib/legacy/zstd_v04.c", "lib/legacy/zstd_v05.c",
                "lib/legacy/zstd_v06.c", "lib/legacy/zstd_v07.c"
            ],
            publicHeadersPath: "include",
            cSettings: [.define("ZSTD_LEGACY_SUPPORT", to: "4"), .define("ZSTD_DISABLE_ASM", to: "1")]
        ),
        .target(
            name: "UltraViewerProtocol",
            dependencies: ["CZstd", "CG722"],
            path: "Sources/UltraViewerProtocol"
        ),
        .target(name: "iOSViewerKit", dependencies: ["UltraViewerProtocol"]),
        .executableTarget(name: "iOSViewerApp", dependencies: ["iOSViewerKit"]),
        .executableTarget(name: "iOSViewerScaffold", dependencies: ["iOSViewerKit"]),
        .testTarget(name: "iOSViewerKitTests", dependencies: ["iOSViewerKit"])
    ]
)
