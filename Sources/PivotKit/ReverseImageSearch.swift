// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Reverse image search engines.
///
/// Several rather than one, because they index different corpora and routinely disagree: a
/// face that Google cannot place is often on Yandex, and TinEye is the one that finds the
/// earliest copy rather than the most similar. Running the same image through all of them is
/// standard practice, and the whole point of doing it from a menu is that it takes one click
/// each instead of a manual upload each.
public enum ReverseImageSearch {

    public struct Engine: Sendable {
        public let name: String
        public let template: String

        /// Nil when the image cannot be handed over by URL — a `data:` or `blob:` image has no
        /// address a search engine could fetch, and offering the lookup anyway would produce
        /// a broken page rather than a result.
        public func url(for imageURL: URL) -> URL? {
            guard let scheme = imageURL.scheme, scheme == "http" || scheme == "https" else {
                return nil
            }
            guard let encoded = imageURL.absoluteString.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))
            ) else { return nil }
            return URL(string: template.replacingOccurrences(of: "{url}", with: encoded))
        }
    }

    public static let engines: [Engine] = [
        Engine(name: "Google Lens", template: "https://lens.google.com/uploadbyurl?url={url}"),
        Engine(name: "Yandex", template: "https://yandex.com/images/search?rpt=imageview&url={url}"),
        Engine(name: "Bing", template: "https://www.bing.com/images/search?view=detailv2&iss=sbi&q=imgurl:{url}"),
        Engine(name: "TinEye", template: "https://tineye.com/search?url={url}"),
    ]
}
