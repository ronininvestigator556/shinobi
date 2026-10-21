// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The set a fresh install starts with.
///
/// Chosen to be the places an investigator actually opens rather than an exhaustive directory
/// — the long link-lists that circulate in the field are reference documents, and a bookmark
/// menu that reads like one is no faster than a search.
///
/// Two rules were applied throughout. A `{query}` template is only used where the site's
/// search URL is known to be stable; everywhere else the entry is the site itself, because a
/// bookmark that lands on a 404 is worse than one that takes a second click. And anything
/// needing an account or payment says so, since finding that out at the paywall wastes the trip.
///
/// This is a starting point, not a recommendation of any particular service. Some of these
/// operate in areas — bulk personal data, facial recognition — where what is lawful varies by
/// jurisdiction and by the purpose of the search. That judgement is the investigator's.
public enum StarterBookmarks {

    public static func all() -> [Bookmark] { entries.map(\.bookmark) + StateResources.all() }

    /// Folders in the order they should appear.
    public static let folderOrder = [
        "Search", "People", "Courts & Records", "Business", "Property",
        "Usernames & Accounts", "Email & Phone", "Domains & Infrastructure",
        "Images & Faces", "Archives", "Maps & Geolocation", "Transport",
        "Breaches", "Reference",
    ] + StateResources.folderNames

    private struct Entry {
        let bookmark: Bookmark
        init(_ title: String, _ url: String, _ folder: String,
             keyword: String? = nil, note: String? = nil, account: Bool = false) {
            bookmark = Bookmark(title: title, url: url, folder: folder,
                                keyword: keyword, note: note, requiresAccount: account)
        }
    }

    private static let entries: [Entry] = [
        // Search
        Entry("DuckDuckGo", "https://duckduckgo.com/?q={query}", "Search", keyword: "ddg"),
        Entry("Google", "https://www.google.com/search?q={query}", "Search", keyword: "g"),
        Entry("Google (verbatim)", "https://www.google.com/search?q={query}&tbs=li:1", "Search",
              note: "Disables synonym expansion — useful for exact names and strings."),
        Entry("Bing", "https://www.bing.com/search?q={query}", "Search"),
        Entry("Yandex", "https://yandex.com/search/?text={query}", "Search",
              note: "Indexes material the others often do not, particularly Russian-language."),
        Entry("Startpage", "https://www.startpage.com/sp/search?query={query}", "Search"),
        Entry("Million Short", "https://millionshort.com/", "Search",
              note: "Removes the most popular sites from results, surfacing the rest."),

        // People
        Entry("TruePeopleSearch", "https://www.truepeoplesearch.com/", "People"),
        Entry("FastPeopleSearch", "https://www.fastpeoplesearch.com/", "People"),
        Entry("ThatsThem", "https://thatsthem.com/", "People"),
        Entry("Radaris", "https://radaris.com/", "People"),
        Entry("WebMii", "https://webmii.com/", "People"),
        Entry("Spokeo", "https://www.spokeo.com/", "People", account: true),
        Entry("BeenVerified", "https://www.beenverified.com/", "People", account: true),
        Entry("FamilySearch", "https://www.familysearch.org/en/search/", "People", note: "Free account. Strong for genealogy, obituaries and historical records.", account: true),
        Entry("Legacy obituaries", "https://www.legacy.com/us/obituaries/", "People",
              note: "Obituaries name relatives, which is often the link you are missing."),

        // Courts & Records
        Entry("CourtListener", "https://www.courtlistener.com/?q={query}", "Courts & Records",
              note: "Free federal and state opinions, dockets and PACER mirrors."),
        Entry("PACER", "https://pacer.uscourts.gov/", "Courts & Records", note: "US federal dockets. Paid per page.", account: true),
        Entry("UniCourt", "https://unicourt.com/", "Courts & Records", account: true),
        Entry("Justia dockets", "https://dockets.justia.com/", "Courts & Records"),
        Entry("Government attic", "https://www.governmentattic.org/", "Courts & Records",
              note: "Released FOIA documents."),
        Entry("MuckRock", "https://www.muckrock.com/", "Courts & Records",
              note: "FOIA requests and their responses, filed publicly."),
        Entry("BOP inmate locator", "https://www.bop.gov/inmateloc/", "Courts & Records",
              note: "US federal inmates."),

        // Business
        Entry("OpenCorporates", "https://opencorporates.com/companies?q={query}", "Business",
              note: "Company registries across many jurisdictions in one search."),
        Entry("SEC EDGAR", "https://www.sec.gov/cgi-bin/browse-edgar?company={query}&action=getcompany",
              "Business", note: "US filings. Officers, ownership and addresses."),
        Entry("SEC full-text search", "https://efts.sec.gov/LATEST/search-index?q={query}", "Business",
              note: "Searches inside filings rather than just company names."),
        Entry("Companies House (UK)",
              "https://find-and-update.company-information.service.gov.uk/search?q={query}", "Business"),
        Entry("OpenSanctions", "https://www.opensanctions.org/search/?q={query}", "Business",
              note: "Sanctions, PEPs and watchlists."),
        Entry("OFAC sanctions search", "https://sanctionssearch.ofac.treas.gov/", "Business"),
        Entry("SAM.gov", "https://sam.gov/search/", "Business",
              note: "US federal contractors and exclusions."),
        Entry("Aleph (OCCRP)", "https://aleph.occrp.org/", "Business", note: "Leaks, registries and investigative datasets.", account: true),

        // Property
        Entry("NETR Online", "https://publicrecords.netronline.com/", "Property",
              note: "Directory of US county assessor and recorder sites, by state."),
        Entry("Regrid", "https://app.regrid.com/", "Property", note: "Parcel data nationwide.", account: true),
        Entry("HUD resource locator", "https://resources.hud.gov/", "Property"),

        // Usernames & Accounts
        Entry("WhatsMyName", "https://whatsmyname.app/", "Usernames & Accounts",
              note: "Checks a username across hundreds of sites."),
        Entry("Instant Username Search", "https://instantusername.com/", "Usernames & Accounts"),
        Entry("Social Searcher", "https://www.social-searcher.com/", "Usernames & Accounts"),
        Entry("Reddit user", "https://www.reddit.com/user/{query}", "Usernames & Accounts"),
        Entry("GitHub user", "https://github.com/{query}", "Usernames & Accounts"),
        Entry("Redditor analysis", "https://www.redditmetis.com/", "Usernames & Accounts",
              note: "Summarises a Reddit account's history and habits."),

        // Email & Phone
        Entry("Have I Been Pwned", "https://haveibeenpwned.com/account/{query}", "Email & Phone",
              note: "Which breaches an address appears in."),
        Entry("EmailRep", "https://emailrep.io/", "Email & Phone"),
        Entry("Epieos", "https://epieos.com/", "Email & Phone",
              note: "What an address or number is registered against."),
        Entry("Hunter", "https://hunter.io/", "Email & Phone", note: "Address patterns for a domain.", account: true),
        Entry("NumLookup", "https://www.numlookup.com/", "Email & Phone"),
        Entry("Truecaller", "https://www.truecaller.com/", "Email & Phone", account: true),

        // Domains & Infrastructure
        Entry("Whois", "https://who.is/whois/{query}", "Domains & Infrastructure"),
        Entry("crt.sh", "https://crt.sh/?q={query}", "Domains & Infrastructure",
              note: "Certificate transparency. Finds subdomains registration hides."),
        Entry("Shodan", "https://www.shodan.io/search?query={query}", "Domains & Infrastructure",
              account: true),
        Entry("Censys", "https://search.censys.io/search?resource=hosts&q={query}",
              "Domains & Infrastructure", account: true),
        Entry("urlscan.io", "https://urlscan.io/search/#{query}", "Domains & Infrastructure"),
        Entry("VirusTotal", "https://www.virustotal.com/gui/search/{query}",
              "Domains & Infrastructure"),
        Entry("SecurityTrails", "https://securitytrails.com/", "Domains & Infrastructure",
              note: "Historical DNS and WHOIS.", account: true),
        Entry("ViewDNS", "https://viewdns.info/", "Domains & Infrastructure",
              note: "Reverse IP, reverse WHOIS and DNS history in one place."),
        Entry("BGP.he.net", "https://bgp.he.net/", "Domains & Infrastructure"),
        Entry("BuiltWith", "https://builtwith.com/{query}", "Domains & Infrastructure",
              note: "What a site runs on, and other sites sharing its identifiers."),

        // Images & Faces
        Entry("Google Lens", "https://lens.google.com/", "Images & Faces"),
        Entry("Yandex Images", "https://yandex.com/images/", "Images & Faces",
              note: "Generally the strongest for faces and places."),
        Entry("TinEye", "https://tineye.com/", "Images & Faces",
              note: "Finds the earliest copy rather than the most similar."),
        Entry("Bing Visual Search", "https://www.bing.com/visualsearch", "Images & Faces"),
        Entry("PimEyes", "https://pimeyes.com/en", "Images & Faces", note: "Facial recognition. Check what is lawful for your purpose and jurisdiction.", account: true),
        Entry("FotoForensics", "https://fotoforensics.com/", "Images & Faces",
              note: "Error level analysis and metadata for manipulation checks."),
        Entry("WeVerify plugin", "https://weverify.eu/verification-plugin/", "Images & Faces",
              note: "Video verification and keyframe extraction. Formerly InVID."),

        // Archives
        Entry("Wayback Machine", "https://web.archive.org/web/*/{query}", "Archives"),
        Entry("archive.today", "https://archive.ph/newest/{query}", "Archives",
              note: "Catches pages the Wayback Machine is blocked from."),
        Entry("Wayback save page", "https://web.archive.org/save/", "Archives",
              note: "Archives a page publicly and permanently. Consider who can see that."),

        // Maps & Geolocation
        Entry("Google Maps", "https://www.google.com/maps", "Maps & Geolocation"),
        Entry("Google Earth", "https://earth.google.com/web/", "Maps & Geolocation",
              note: "Historical imagery, which street view often lacks."),
        Entry("Bing Maps", "https://www.bing.com/maps", "Maps & Geolocation",
              note: "Bird's eye imagery at angles Google does not carry."),
        Entry("OpenStreetMap", "https://www.openstreetmap.org/", "Maps & Geolocation"),
        Entry("Mapillary", "https://www.mapillary.com/app/", "Maps & Geolocation",
              note: "Street-level imagery where the big providers have none."),
        Entry("SunCalc", "https://www.suncalc.org/", "Maps & Geolocation",
              note: "Sun position by date and place — dates a photograph from its shadows."),
        Entry("Overpass Turbo", "https://overpass-turbo.eu/", "Maps & Geolocation",
              note: "Query OpenStreetMap for features: every petrol station in a radius, say."),

        // Transport
        Entry("FlightAware", "https://www.flightaware.com/", "Transport"),
        Entry("ADS-B Exchange", "https://globe.adsbexchange.com/", "Transport",
              note: "Unfiltered flight tracking, including aircraft others hide."),
        Entry("MarineTraffic", "https://www.marinetraffic.com/", "Transport"),
        Entry("NICB VINCheck", "https://www.nicb.org/vincheck", "Transport",
              note: "Theft and salvage records for a US VIN."),
        Entry("NHTSA VIN decoder", "https://vpic.nhtsa.dot.gov/decoder/", "Transport"),

        // Breaches
        Entry("Intelligence X", "https://intelx.io/", "Breaches", account: true),
        Entry("Dehashed", "https://dehashed.com/", "Breaches", account: true),
        Entry("Breach directory", "https://breachdirectory.org/", "Breaches"),

        // Reference
        Entry("Bellingcat toolkit", "https://bellingcat.gitbook.io/toolkit", "Reference",
              note: "The field's working list of tools, kept current."),
        Entry("OSINT Framework", "https://osintframework.com/", "Reference"),
        Entry("IntelTechniques tools", "https://inteltechniques.com/tools/", "Reference"),
        Entry("Time zone converter", "https://www.timeanddate.com/worldclock/converter.html",
              "Reference", note: "Post timestamps are rarely in your zone."),
        Entry("Epoch converter", "https://www.epochconverter.com/", "Reference"),
        Entry("CyberChef", "https://gchq.github.io/CyberChef/", "Reference",
              note: "Decoding, hashing and data mangling in the browser."),
    ]
}
