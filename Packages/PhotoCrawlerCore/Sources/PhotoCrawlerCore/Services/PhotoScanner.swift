import Foundation
import Photos
#if canImport(os)
import os
#endif

/// Scans the Photos library for new photos using date-based incremental scanning.
public actor PhotoScanner {
    private let config: CrawlerConfiguration
    private let stateStore: StateStore

    #if canImport(os)
    private let logger = Logger(subsystem: "com.photocrawler", category: "PhotoScanner")
    #endif

    public init(config: CrawlerConfiguration, stateStore: StateStore) {
        self.config = config
        self.stateStore = stateStore
    }

    /// Request photo library authorization.
    public static func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Fetch unprocessed photos from the configured album.
    /// Photos whose asset ID is in `existingAssetIds` are skipped (already have a note in the vault).
    public func fetchNewPhotos(existingAssetIds: Set<String>) async throws -> [(asset: PHAsset, data: Data)] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized else {
            throw PhotoScannerError.notAuthorized(status)
        }

        // Find the album
        guard let album = findAlbum(named: config.albumName) else {
            throw PhotoScannerError.albumNotFound(config.albumName)
        }

        let assets = fetchAllAssets(in: album)

        // Only load image data for photos that don't already have a vault note
        let newAssets = assets.filter { !existingAssetIds.contains($0.localIdentifier) }

        #if canImport(os)
        logger.info("Album '\(self.config.albumName)': \(assets.count) total, \(newAssets.count) new")
        #endif

        var results: [(asset: PHAsset, data: Data)] = []
        for asset in newAssets {
            if let data = try await loadImageData(for: asset) {
                results.append((asset: asset, data: data))
            }
        }

        return results
    }

    // MARK: - Private Methods

    private func findAlbum(named name: String) -> PHAssetCollection? {
        let fetchResult = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        var found: PHAssetCollection?
        fetchResult.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == name {
                found = collection
                stop.pointee = true
            }
        }
        return found
    }

    private func fetchAllAssets(in album: PHAssetCollection) -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(in: album, options: fetchOptions)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        return assets
    }

    private func loadImageData(for asset: PHAsset) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }
}

public enum PhotoScannerError: LocalizedError, Sendable {
    case notAuthorized(PHAuthorizationStatus)
    case fetchFailed(String)
    case albumNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized(let status):
            return "Photo library not authorized (status: \(status.rawValue))"
        case .fetchFailed(let detail):
            return "Failed to fetch photos: \(detail)"
        case .albumNotFound(let name):
            return "Album '\(name)' not found in Photos. Create it in the Photos app first, then add photos you want to capture."
        }
    }
}
