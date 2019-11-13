//
//  MP42FileAdditions.swift
//  Subler
//
//  Created by Damiano Galassi on 09/10/2017.
//

import Foundation
import MP42Foundation

private extension String {
    func condensingWhitespace() -> String {
        return self.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension MP42File {

    enum TrackHDType : Int {
        case hd720p = 1
        case hd1080p = 2
        case hd4k = 3
    }

    var hdType: TrackHDType? {
        for track in tracks(withMediaType: kMP42MediaType_Video) as! [MP42VideoTrack] {
            if (track.width > 1920 && track.height > 1088) {
                return nil // .hd4k 4k breaks AppleTV streaming
            } else if (track.width > 1280 || track.height > 720) && track.width <= 1920 && track.height <= 1088 {
                return .hd1080p
            } else if track.width >= 960 && track.height >= 720 || track.width >= 1280 {
                return .hd720p
            }
        }
        return nil
    }

    func firstSourceURL() -> URL? {
        for track in tracks {
            if track.url != nil {
                return track.url
            }
        }
        return nil
    }

    func extractSearchTerms(fallbackURL: URL?) -> MetadataSearchTerms {
        if let tvShow = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyTVShow).first?.stringValue,
            let season = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyTVSeason).first?.numberValue?.intValue,
            let number = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyTVEpisodeNumber).first?.numberValue?.intValue,
            let mediaKind = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyMediaKind).first?.numberValue?.intValue,
            mediaKind == MetadataResult.MediaKindType.tvShow.rawValue {
            return MetadataSearchTerms.tvShow(seriesName: tvShow, season: season, episode: number)
        }
        else if let title = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyName).first?.stringValue,
            let _ = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyReleaseDate).first?.stringValue,
            let mediaKind = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyMediaKind).first?.numberValue?.intValue,
            mediaKind == MetadataResult.MediaKindType.movie.rawValue {
            return MetadataSearchTerms.movie(title: title)
        }
        else if let url = firstSourceURL() ?? fallbackURL {
            let parsed = url.deletingPathExtension().lastPathComponent.parsedAsFilename()

            switch parsed {
            case .none:
                let title = url.deletingPathExtension().lastPathComponent
                return MetadataSearchTerms.movie(title: title)

            case .tvShow, .movie:
                return parsed
            }
        }
        return MetadataSearchTerms.none
    }

    private func outputNameFormat(mediaKind: Int) -> [Token]? {
        if mediaKind == MetadataResult.MediaKindType.tvShow.rawValue {
            return UserDefaults.standard.tokenArray(forKey: "SBTVShowFormatTokens")
        } else if mediaKind == MetadataResult.MediaKindType.movie.rawValue {
            return UserDefaults.standard.tokenArray(forKey: "SBMovieFormatTokens")
        }
        return nil
    }

    // MARK: File name

    func preferredFileName() -> String? {
        if let mediaKind = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyMediaKind).first?.numberValue?.intValue,
            (mediaKind == MetadataResult.MediaKindType.tvShow.rawValue && UserDefaults.standard.bool(forKey: "SBSetTVShowFormat")) ||
                (mediaKind == MetadataResult.MediaKindType.movie.rawValue && UserDefaults.standard.bool(forKey: "SBSetMovieFormat")),
            let name = formattedFileName() {
            return name
        } else {
            return tracks.compactMap { $0.url }.first?.deletingPathExtension().lastPathComponent
        }
    }

    func formattedFileName() -> String? {
        guard let mediaKind = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyMediaKind).first?.numberValue?.intValue,
              let format = outputNameFormat(mediaKind: mediaKind)
            else { return nil }

        let separators = CharacterSet(charactersIn: "{}")
        var name = ""

        for token in format {
            if token.isPlaceholder {
                let trimmedToken = token.text.trimmingCharacters(in: separators)
                let metadataItems = metadata.metadataItemsFiltered(byIdentifier: trimmedToken)

                if let item = metadataItems.first {
                    name.append(token.format(metadataItem: item))
                }
            } else {
                name.append(token.text)
            }
        }

        name = name.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "/", with: "-").condensingWhitespace()

        return name.isEmpty ? nil : name
    }
}

extension MP42AudioTrack {

    var outputChannels: UInt32 {
        if let cs = conversionSettings as? MP42AudioConversionSettings {
            if cs.mixDown == kMP42AudioMixdown_Mono || channels == 1 {
                return 1
            } else if cs.mixDown == kMP42AudioMixdown_None {
                return channels
            } else {
                return 2
            }
        } else {
            return channels
        }
    }

    var prettyTrackName: String {
        let channelCount = outputChannels

        // Use channel count to determine track name
        if channelCount == 1 {
            return "Mono Audio"
        } else if channelCount == 2 {
            return "Stereo Audio"
        } else {
            return "Surround Audio"
        }
    }
}
