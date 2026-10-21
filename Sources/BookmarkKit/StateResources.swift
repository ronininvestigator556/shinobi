// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Per-state public-records lookups, seeded as a bookmark folder for every US state.
///
/// Each state is its own folder (the model is one flat level of grouping), holding the
/// record searches an investigator reaches for: the Secretary of State business registry,
/// the statewide court-case index, the Department of Corrections inmate locator, the sex-
/// offender registry, property records, and professional-license verification.
///
/// Rules applied throughout:
/// - Official government sources only. A handful of states route a public search through a
///   state-contracted vendor (OffenderWatch's icrimewatch.net, VINE's vinelink.com); those
///   are used only where the state provides no `.gov` search of its own, and are noted.
/// - Property records are county-level in almost every state, so those entries point at the
///   state's county directory on NETR Online. The dozen states with a genuine statewide
///   parcel/GIS portal link to it directly.
/// - Where a search is paid, registration-gated, or does not exist statewide, the note says
///   so — finding that out at the paywall or a dead link wastes the trip.
/// - Professional licensing with no single statewide portal ("varies by board") is omitted
///   rather than pointed at a guess.
///
/// These are starting points, current as of compilation; state systems move. Accuracy is the
/// investigator's to confirm for anything that matters to a case.
public enum StateResources {

    /// Every state's record links, flattened into bookmarks filed under the state's name.
    public static func all() -> [Bookmark] {
        states.flatMap { state in
            state.links.map { link in
                Bookmark(title: link.title, url: link.url, folder: state.name, note: link.note)
            }
        }
    }

    /// The state folder names, in order, for appending to the bookmark menu.
    public static var folderNames: [String] { states.map(\.name) }

    struct Link {
        let title: String
        let url: String
        let note: String?
        init(_ title: String, _ url: String, _ note: String? = nil) {
            self.title = title; self.url = url; self.note = note
        }
    }

    struct StateEntry {
        let name: String
        let links: [Link]
        init(_ name: String, _ links: [Link]) { self.name = name; self.links = links }
    }

    static let states: [StateEntry] = [
        StateEntry("Alabama", [
            Link("Business Search", "https://arc-sos.state.al.us/CGI/CORPNAME.MBR/INPUT"),
            Link("Court Records", "https://v2.alacourt.com/", "Paid subscription; pay-per-case at pa.alacourt.com"),
            Link("Inmate Search", "https://www.doc.alabama.gov/inmate-search"),
            Link("Sex Offender Registry", "https://app.alea.gov/community/Default.aspx", "ALEA — choose Sex Offender Search"),
            Link("Property Records", "https://publicrecords.netronline.com/state/AL", "County assessor/recorder directory (NETR)"),
        ]),
        StateEntry("Alaska", [
            Link("Business Search", "https://www.commerce.alaska.gov/cbp/main/Search/Entities"),
            Link("Court Records", "https://records.courts.alaska.gov/"),
            Link("Inmate Search", "https://www.vinelink.com", "DOC has no .gov locator; uses VINE"),
            Link("Sex Offender Registry", "https://sor.dps.alaska.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/AK", "Borough assessor directory (NETR)"),
            Link("License Lookup", "https://www.commerce.alaska.gov/cbp/main/Search/Professional"),
        ]),
        StateEntry("Arizona", [
            Link("Business Search", "https://arizonabusinesscenter.azcc.gov/EntitySearch/Index"),
            Link("Court Records", "https://apps.azcourts.gov/publicaccess/", "Covers 177 of 184 courts"),
            Link("Inmate Search", "https://azadc.gov/inmate-data-search"),
            Link("Sex Offender Registry", "https://www.azdps.gov/services/public/offender"),
            Link("Property Records", "https://publicrecords.netronline.com/state/AZ", "County assessor/recorder directory (NETR)"),
        ]),
        StateEntry("Arkansas", [
            Link("Business Search", "https://sos-corp-search.ark.org/corps"),
            Link("Court Records", "https://caseinfo.arcourts.gov/cconnect/"),
            Link("Inmate Search", "https://inmate.ark.org/"),
            Link("Sex Offender Registry", "https://www.ark.org/offender-search/index.php"),
            Link("Property Records", "https://publicrecords.netronline.com/state/AR", "County assessor/recorder directory (NETR)"),
        ]),
        StateEntry("California", [
            Link("Business Search", "https://bizfileonline.sos.ca.gov/search/business"),
            Link("Court Records", "https://www.courts.ca.gov/find-my-court.htm", "No statewide index — each county Superior Court runs its own"),
            Link("Inmate Search", "https://inmatelocator.cdcr.ca.gov/"),
            Link("Sex Offender Registry", "https://www.meganslaw.ca.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/CA", "County assessor/recorder directory (NETR)"),
            Link("License Lookup", "https://search.dca.ca.gov/", "Most boards; contractors (CSLB) separate"),
        ]),
        StateEntry("Colorado", [
            Link("Business Search", "https://www.coloradosos.gov/biz/BusinessEntityCriteriaExt.do"),
            Link("Court Records", "https://www.coloradojudicial.gov/dockets", "Docket-only; full records via paid ICCES"),
            Link("Inmate Search", "https://cdoc.colorado.gov/", "DOC site — use Offender Search"),
            Link("Sex Offender Registry", "https://apps.colorado.gov/apps/dps/sor/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/CO", "County assessor/recorder directory (NETR)"),
            Link("License Lookup", "https://apps.colorado.gov/dora/licensing/Lookup/LicenseLookup.aspx"),
        ]),
        StateEntry("Connecticut", [
            Link("Business Search", "https://service.ct.gov/business/s/onlinebusinesssearch"),
            Link("Court Records", "https://civilinquiry.jud.ct.gov/", "Civil/family; criminal at jud2.ct.gov/crdockets"),
            Link("Inmate Search", "http://www.ctinmateinfo.state.ct.us/"),
            Link("Sex Offender Registry", "https://portal.ct.gov/DESPP", "DESPP registry; search is vendor-hosted"),
            Link("Property Records", "https://publicrecords.netronline.com/state/CT", "Town assessor/clerk directory (NETR)"),
            Link("License Lookup", "https://www.elicense.ct.gov/"),
        ]),
        StateEntry("Delaware", [
            Link("Business Search", "https://icis.corp.delaware.gov/ecorp/entitysearch/namesearch.aspx"),
            Link("Court Records", "https://courtconnect.courts.delaware.gov/"),
            Link("Inmate Search", "https://www.vinelink.com", "DOC has no .gov locator; uses VINE"),
            Link("Sex Offender Registry", "https://sexoffender.dsp.delaware.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/DE", "County assessor/recorder directory (NETR)"),
            Link("License Lookup", "https://delpros.delaware.gov/OH_VerifyLicense"),
        ]),
        StateEntry("Florida", [
            Link("Business Search", "https://search.sunbiz.org/Inquiry/CorporationSearch/ByName"),
            Link("Court Records", "https://www.flclerks.com/", "No statewide index — each county Clerk of Court"),
            Link("Inmate Search", "https://pubapps.fdc.myflorida.com/OffenderSearch/"),
            Link("Sex Offender Registry", "https://offender.fdle.state.fl.us/offender/sops/home.jsf"),
            Link("Property Records", "https://publicrecords.netronline.com/state/FL", "County property appraiser directory (NETR)"),
            Link("License Lookup", "https://www.myfloridalicense.com/wl11.asp", "DBPR; health professions separate at FL DOH"),
        ]),
        StateEntry("Georgia", [
            Link("Business Search", "https://ecorp.sos.ga.gov/BusinessSearch"),
            Link("Court Records", "https://georgiacourts.gov/", "No unified statewide index — by county clerk"),
            Link("Inmate Search", "https://gdc.georgia.gov/", "GDC — Find an Offender"),
            Link("Sex Offender Registry", "https://state.sor.gbi.ga.gov/Sort_Public/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/GA", "County assessor/clerk directory (NETR)"),
            Link("License Lookup", "https://verify.sos.ga.gov/verification/"),
        ]),
        StateEntry("Hawaii", [
            Link("Business Search", "https://hbe.dcca.hawaii.gov/"),
            Link("Court Records", "https://www.courts.state.hi.us/legal_references/records/search_court_records"),
            Link("Inmate Search", "https://www.vinelink.com", "No state .gov locator; uses VINE"),
            Link("Sex Offender Registry", "https://sexoffenders.ehawaii.gov/coveredoffender/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/HI", "County assessor directory (NETR)"),
            Link("License Lookup", "https://mypvl.dcca.hawaii.gov/public-license-search"),
        ]),
        StateEntry("Idaho", [
            Link("Business Search", "https://sosbiz.idaho.gov/search/business"),
            Link("Court Records", "https://mycourts.idaho.gov/odysseyportal"),
            Link("Inmate Search", "https://www.idoc.idaho.gov/content/prisons/offender_search"),
            Link("Sex Offender Registry", "https://apps.isp.idaho.gov/sor_id/search.html"),
            Link("Property Records", "https://publicrecords.netronline.com/state/ID", "County assessor/recorder directory (NETR)"),
            Link("License Lookup", "https://dopl.idaho.gov/license-search/"),
        ]),
        StateEntry("Illinois", [
            Link("Business Search", "https://apps.ilsos.gov/businessentitysearch/"),
            Link("Court Records", "https://researchil.tylerhost.net/CourtRecordsSearch/Home#/home", "re:SearchIL — registration required"),
            Link("Inmate Search", "https://idoc.illinois.gov/offender/inmatesearch.html"),
            Link("Sex Offender Registry", "https://isp.illinois.gov/Sor"),
            Link("Property Records", "https://publicrecords.netronline.com/state/IL", "County assessor/recorder directory (NETR)"),
            Link("License Lookup", "https://idfpr.illinois.gov/checklicense.html"),
        ]),
        StateEntry("Indiana", [
            Link("Business Search", "https://bsd.sos.in.gov/PublicBusinessSearch"),
            Link("Court Records", "https://public.courts.in.gov/mycase/"),
            Link("Inmate Search", "https://offenderlocator.idoc.in.gov/"),
            Link("Sex Offender Registry", "https://www.icrimewatch.net/indiana.php", "Official registry on OffenderWatch (non-.gov)"),
            Link("Property Records", "https://publicrecords.netronline.com/state/IN", "County assessor/recorder directory (NETR)"),
            Link("License Lookup", "https://mylicense.in.gov/everification/"),
        ]),
        StateEntry("Iowa", [
            Link("Business Search", "https://sos.iowa.gov/search/business"),
            Link("Court Records", "https://www.iowacourts.state.ia.us/ESAWebApp/DefaultFrame"),
            Link("Inmate Search", "https://doc-search.iowa.gov/"),
            Link("Sex Offender Registry", "https://iowasexoffender.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/IA", "County assessor/recorder directory (NETR)"),
            Link("License Lookup", "https://dial.iowa.gov/licenses", "Central DIAL portal; some boards verify separately"),
        ]),
        StateEntry("Kansas", [
            Link("Business Search", "https://www.sos.ks.gov/eforms/BusinessEntity/Search.aspx"),
            Link("Court Records", "https://casesearch.kscourts.gov/"),
            Link("Inmate Search", "https://kdocrepository.doc.ks.gov/kasper/", "KASPER"),
            Link("Sex Offender Registry", "https://www.kbi.ks.gov/registeredoffender/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/KS", "County appraiser/register directory (NETR)"),
            Link("License Lookup", "https://prolicenseverify.ks.gov/"),
        ]),
        StateEntry("Kentucky", [
            Link("Business Search", "https://sosbes.sos.ky.gov/BusSearchNProfile/search.aspx"),
            Link("Court Records", "https://kcoj.kycourts.net/kyecourts/login/guestlogin", "Free guest login"),
            Link("Inmate Search", "https://kool.corrections.ky.gov/", "Kentucky Online Offender Lookup"),
            Link("Sex Offender Registry", "https://kspsor.state.ky.us/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/KY", "County PVA/clerk directory (NETR)"),
        ]),
        StateEntry("Louisiana", [
            Link("Business Search", "https://coraweb.sos.la.gov/CommercialSearch/CommercialSearch.aspx"),
            Link("Court Records", "https://www.lasc.org", "No statewide index — searched parish-by-parish"),
            Link("Inmate Search", "https://doc.louisiana.gov/offender-locator/"),
            Link("Sex Offender Registry", "https://lsp.org/community-outreach/sex-offender-registry/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/LA", "Parish assessor/clerk directory (NETR)"),
        ]),
        StateEntry("Maine", [
            Link("Business Search", "https://apps3.web.maine.gov/nei-sos-icrs/ICRS"),
            Link("Court Records", "https://researchmaine.tylerhost.net/CourtRecordsSearch", "re:SearchMaine — registration; partial coverage"),
            Link("Inmate Search", "https://apps1.web.maine.gov/online/correctionssearch/"),
            Link("Sex Offender Registry", "https://sor.informe.org/cgi-bin/sor/index.pl"),
            Link("Property Records", "https://publicrecords.netronline.com/state/ME", "County Registry of Deeds directory (NETR)"),
            Link("License Lookup", "https://www.pfr.maine.gov/ALMSOnline/ALMSQuery/Welcome.aspx"),
        ]),
        StateEntry("Maryland", [
            Link("Business Search", "https://egov.maryland.gov/businessexpress/entitysearch"),
            Link("Court Records", "https://casesearch.courts.state.md.us/casesearch/"),
            Link("Inmate Search", "https://dpscs.maryland.gov/services/ii-locator.shtml"),
            Link("Sex Offender Registry", "https://dpscs.maryland.gov/onlineservs/socem/default.shtml"),
            Link("Property Records", "https://sdat.dat.maryland.gov/", "Statewide SDAT Real Property search"),
            Link("License Lookup", "https://www.dllr.state.md.us/pq"),
        ]),
        StateEntry("Massachusetts", [
            Link("Business Search", "https://corp.sec.state.ma.us/CorpWeb/CorpSearch/CorpSearch.aspx"),
            Link("Court Records", "https://www.masscourts.org"),
            Link("Inmate Search", "https://www.mass.gov/how-to/find-an-inmate-in-a-massachusetts-prison"),
            Link("Sex Offender Registry", "https://www.mass.gov/orgs/sex-offender-registry-board"),
            Link("Property Records", "https://www.mass.gov/info-details/massachusetts-interactive-property-map", "Statewide property map (MassGIS)"),
            Link("License Lookup", "https://www.mass.gov/info-details/division-of-occupational-licensure-check-a-license"),
        ]),
        StateEntry("Michigan", [
            Link("Business Search", "https://www.michigan.gov/corpentitysearch"),
            Link("Court Records", "https://micourt.courts.michigan.gov/case-search"),
            Link("Inmate Search", "https://www.michigan.gov/corrections/otis"),
            Link("Sex Offender Registry", "https://www.mspsor.com/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/MI", "County register/equalization directory (NETR)"),
            Link("License Lookup", "https://www.michigan.gov/lara", "LARA — search runs on the MiPLUS system"),
        ]),
        StateEntry("Minnesota", [
            Link("Business Search", "https://mblsportal.sos.mn.gov/Business/Search"),
            Link("Court Records", "https://publicaccess.courts.state.mn.us/"),
            Link("Inmate Search", "https://coms.doc.state.mn.us/PublicViewer"),
            Link("Sex Offender Registry", "https://coms.doc.state.mn.us/publicregistrantsearch"),
            Link("Property Records", "https://publicrecords.netronline.com/state/MN", "County assessor/recorder directory (NETR)"),
        ]),
        StateEntry("Mississippi", [
            Link("Business Search", "https://corp.sos.ms.gov/corp/soskb/csearch.asp"),
            Link("Court Records", "https://courts.ms.gov", "MEC public access (PAMEC) is subscription-based"),
            Link("Inmate Search", "https://www.mdoc.ms.gov/"),
            Link("Sex Offender Registry", "https://state.sor.dps.ms.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/MS", "County assessor/chancery clerk directory (NETR)"),
        ]),
        StateEntry("Missouri", [
            Link("Business Search", "https://bsd.sos.mo.gov/BusinessEntity/BESearch.aspx"),
            Link("Court Records", "https://www.courts.mo.gov/casenet/base/welcome.do", "Case.net"),
            Link("Inmate Search", "https://web.mo.gov/doc/offSearchWeb/"),
            Link("Sex Offender Registry", "https://www.mshp.dps.missouri.gov/MSHPWeb/PatrolDivisions/CRID/SOR/SORPage.html"),
            Link("Property Records", "https://publicrecords.netronline.com/state/MO", "County assessor/recorder directory (NETR)"),
            Link("License Lookup", "https://pr.mo.gov/licensee-search-detail.asp"),
        ]),
        StateEntry("Montana", [
            Link("Business Search", "https://biz.sosmt.gov/search"),
            Link("Court Records", "https://dcportal.pubcourts.mt.gov"),
            Link("Inmate Search", "https://offendersearch.mt.gov/conweb"),
            Link("Sex Offender Registry", "https://app.doj.mt.gov/apps/svow/"),
            Link("Property Records", "https://cadastral.mt.gov", "Statewide cadastral/parcel"),
            Link("License Lookup", "https://ebiz.mt.gov/pol"),
        ]),
        StateEntry("Nebraska", [
            Link("Business Search", "https://www.nebraska.gov/sos/corp/corpsearch.cgi"),
            Link("Court Records", "https://www.nebraska.gov/justice"),
            Link("Inmate Search", "https://dcs-inmatesearch.ne.gov/Corrections/COR_input.html"),
            Link("Sex Offender Registry", "https://sor.nebraska.gov/Registry"),
            Link("Property Records", "https://www.nebraskamap.gov/", "Statewide parcel/GIS"),
            Link("License Lookup", "https://www.nebraska.gov/LISSearch/search.cgi", "DHHS health/behavioral licenses"),
        ]),
        StateEntry("Nevada", [
            Link("Business Search", "https://esos.nv.gov/EntitySearch/OnlineEntitySearch"),
            Link("Court Records", "https://caseinfo.nvsupremecourt.us/public/caseSearch.do", "Appellate only; trial courts per-county"),
            Link("Inmate Search", "https://ofdsearch.doc.nv.gov/"),
            Link("Sex Offender Registry", "https://sexoffenders.nv.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/NV", "County assessor/recorder directory (NETR)"),
        ]),
        StateEntry("New Hampshire", [
            Link("Business Search", "https://quickstart.sos.nh.gov/online/BusinessInquire"),
            Link("Court Records", "https://www.courts.nh.gov/lucie"),
            Link("Inmate Search", "https://business.nh.gov/inmate_locator"),
            Link("Sex Offender Registry", "https://business.nh.gov/nsor/search.aspx"),
            Link("Property Records", "https://granitview.unh.edu/", "Statewide parcel viewer (GRANITView)"),
            Link("License Lookup", "https://forms.nh.gov/licenseverification/"),
        ]),
        StateEntry("New Jersey", [
            Link("Business Search", "https://www.njportal.com/DOR/BusinessNameSearch/Search/BusinessName"),
            Link("Court Records", "https://www.njcourts.gov/public/find-a-case"),
            Link("Inmate Search", "https://www20.state.nj.us/DOC_Inmate/inmatefinder"),
            Link("Sex Offender Registry", "https://www.nj.gov/oag/njsp/sex-offender-registry/index.shtml"),
            Link("Property Records", "https://njogis-newjersey.opendata.arcgis.com/", "Statewide parcel/GIS (NJGIN)"),
            Link("License Lookup", "https://newjersey.mylicense.com/verification/"),
        ]),
        StateEntry("New Mexico", [
            Link("Business Search", "https://enterprise.sos.nm.gov/search"),
            Link("Court Records", "https://caselookup.nmcourts.gov/caselookup"),
            Link("Inmate Search", "https://www.corrections.state.nm.us/offender-search/"),
            Link("Sex Offender Registry", "https://nmsexoffender.dps.state.nm.us/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/NM", "County assessor/clerk directory (NETR)"),
            Link("License Lookup", "https://www.rld.nm.gov/about-us/public-information-hub/verify-a-license/"),
        ]),
        StateEntry("New York", [
            Link("Business Search", "https://apps.dos.ny.gov/publicInquiry/"),
            Link("Court Records", "https://iapps.courts.state.ny.us/webcivil/ewcMain", "WebCivil; criminal via WebCrim"),
            Link("Inmate Search", "https://nysdoccslookup.doccs.ny.gov/"),
            Link("Sex Offender Registry", "https://www.criminaljustice.ny.gov/nsor/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/NY", "County clerk/assessor directory (NETR)"),
            Link("License Lookup", "https://op.nysed.gov/services/verifications/online-verification-searches", "NYSED professions only"),
        ]),
        StateEntry("North Carolina", [
            Link("Business Search", "https://www.sosnc.gov/online_services/search"),
            Link("Court Records", "https://portal-nc.tylertech.cloud/Portal/", "NC eCourts — rolling out by county"),
            Link("Inmate Search", "https://webapps.doc.state.nc.us/opi/offendersearch.do"),
            Link("Sex Offender Registry", "https://sexoffender.ncsbi.gov/"),
            Link("Property Records", "https://www.nconemap.gov/", "Statewide GIS; deeds at county Register of Deeds"),
        ]),
        StateEntry("North Dakota", [
            Link("Business Search", "https://firststop.sos.nd.gov/"),
            Link("Court Records", "https://www.ndcourts.gov/public-access"),
            Link("Inmate Search", "https://docr.nd.gov/resident-lookup"),
            Link("Sex Offender Registry", "https://sexoffender.nd.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/ND", "County directory (NETR)"),
        ]),
        StateEntry("Ohio", [
            Link("Business Search", "https://businesssearch.ohiosos.gov/"),
            Link("Court Records", "https://www.supremecourt.ohio.gov/", "No statewide trial index — by county Clerk of Courts"),
            Link("Inmate Search", "https://appgateway.drc.ohio.gov/OffenderSearch"),
            Link("Sex Offender Registry", "https://www.ohioattorneygeneral.gov/", "eSORN; search is vendor-hosted"),
            Link("Property Records", "https://publicrecords.netronline.com/state/OH", "County auditor/recorder directory (NETR)"),
            Link("License Lookup", "https://elicense.ohio.gov/oh_verifylicense"),
        ]),
        StateEntry("Oklahoma", [
            Link("Business Search", "https://www.sos.ok.gov/corp/corpInquiryFind.aspx"),
            Link("Court Records", "https://www.oscn.net/dockets/Search.aspx", "OSCN; other counties on odcr.com"),
            Link("Inmate Search", "https://okoffender.doc.ok.gov/"),
            Link("Sex Offender Registry", "https://sors.doc.ok.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/OK", "County assessor/clerk directory (NETR)"),
        ]),
        StateEntry("Oregon", [
            Link("Business Search", "https://egov.sos.state.or.us/br/pkg_web_name_srch_inq.login"),
            Link("Court Records", "https://www.courts.oregon.gov/services/online/Pages/ojcin.aspx", "OJCIN; full register is paid"),
            Link("Inmate Search", "https://docpub.state.or.us/OOS/searchCriteria.jsf"),
            Link("Sex Offender Registry", "https://sexoffenders.oregon.gov/"),
            Link("Property Records", "https://www.ormap.net/", "Statewide parcel tax map"),
        ]),
        StateEntry("Pennsylvania", [
            Link("Business Search", "https://www.corporations.pa.gov/search/corpsearch"),
            Link("Court Records", "https://ujsportal.pacourts.us/"),
            Link("Inmate Search", "https://inmatelocator.cor.pa.gov/"),
            Link("Sex Offender Registry", "https://www.meganslaw.psp.pa.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/PA", "County assessor/recorder directory (NETR)"),
            Link("License Lookup", "https://www.pals.pa.gov/"),
        ]),
        StateEntry("Rhode Island", [
            Link("Business Search", "https://business.sos.ri.gov/CorpWeb/CorpSearch/CorpSearch.aspx"),
            Link("Court Records", "https://publicportal.courts.ri.gov/PublicPortal/"),
            Link("Inmate Search", "https://www.vinelink.com", "DOC has no .gov locator; uses VINE"),
            Link("Sex Offender Registry", "https://www.nsopw.gov", "No statewide RI search; national fallback"),
            Link("Property Records", "https://publicrecords.netronline.com/state/RI", "Municipal assessor/clerk directory (NETR)"),
        ]),
        StateEntry("South Carolina", [
            Link("Business Search", "https://businessfilings.sc.gov/BusinessFiling/Entity/Search"),
            Link("Court Records", "https://publicindex.sccourts.org/"),
            Link("Inmate Search", "https://public.doc.state.sc.us/scdc-public/"),
            Link("Sex Offender Registry", "https://scor.sled.sc.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/SC", "County assessor/register directory (NETR)"),
            Link("License Lookup", "https://verify.llronline.com/LicLookup/"),
        ]),
        StateEntry("South Dakota", [
            Link("Business Search", "https://sosenterprise.sd.gov/businessservices/business/FilingSearch.aspx"),
            Link("Court Records", "https://ujspars.sd.gov/", "PARS — $20 per search"),
            Link("Inmate Search", "https://docadultlookup.sd.gov/"),
            Link("Sex Offender Registry", "https://sor.sd.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/SD", "County directory (NETR)"),
        ]),
        StateEntry("Tennessee", [
            Link("Business Search", "https://tnbear.tn.gov/Ecommerce/FilingSearch.aspx"),
            Link("Court Records", "https://www2.tncourts.gov/PublicCaseHistory/", "Appellate; trial partial at tncourtsfinder.tncourts.gov"),
            Link("Inmate Search", "https://foil.app.tn.gov/foil/search.jsp", "Felony Offender Information Lookup"),
            Link("Sex Offender Registry", "https://sor.tbi.tn.gov/"),
            Link("Property Records", "https://assessment.cot.tn.gov/RE_Assessment/", "Statewide assessment/parcel"),
            Link("License Lookup", "https://verify.tn.gov/"),
        ]),
        StateEntry("Texas", [
            Link("Business Search", "https://mycpa.cpa.state.tx.us/coa/", "Free Comptroller entity search; SOSDirect ($1) at sos.state.tx.us/corp"),
            Link("Court Records", "https://research.txcourts.gov/", "re:SearchTX; e-filed docs, no single statewide DB"),
            Link("Inmate Search", "https://inmate.tdcj.texas.gov/InmateSearch/"),
            Link("Sex Offender Registry", "https://publicsite.dps.texas.gov/SexOffenderRegistry"),
            Link("Property Records", "https://publicrecords.netronline.com/state/TX", "County appraisal district/clerk directory (NETR)"),
            Link("License Lookup", "https://www.tdlr.texas.gov/LicenseSearch/", "TDLR; many professions have own boards"),
        ]),
        StateEntry("Utah", [
            Link("Business Search", "https://secure.utah.gov/bes/"),
            Link("Court Records", "https://xchange.utcourts.gov/", "XChange — fees per search/doc"),
            Link("Inmate Search", "https://corrections.utah.gov/offender-search/"),
            Link("Sex Offender Registry", "https://corrections.utah.gov/sex-kidnap-offender-registry/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/UT", "County recorder/assessor directory (NETR)"),
            Link("License Lookup", "https://secure.utah.gov/llv/search/index.html"),
        ]),
        StateEntry("Vermont", [
            Link("Business Search", "https://bizfilings.vermont.gov/online/BusinessInquire/"),
            Link("Court Records", "https://publicportal.courts.vt.gov/Portal/"),
            Link("Inmate Search", "https://doc.vermont.gov/", "DOC Offender Locator link"),
            Link("Sex Offender Registry", "https://vcic.vermont.gov/sex-offender-registry"),
            Link("Property Records", "https://publicrecords.netronline.com/state/VT", "Town clerk/lister directory (NETR)"),
            Link("License Lookup", "https://sos.vermont.gov/opr/look-up-a-professional/"),
        ]),
        StateEntry("Virginia", [
            Link("Business Search", "https://cis.scc.virginia.gov/"),
            Link("Court Records", "https://eapps.courts.state.va.us/ocis/", "OCIS statewide; excludes Fairfax Circuit"),
            Link("Inmate Search", "https://vadoc.virginia.gov/offenders/locator/"),
            Link("Sex Offender Registry", "https://sex-offender.vsp.virginia.gov/sor/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/VA", "County/city assessor/clerk directory (NETR)"),
            Link("License Lookup", "https://www.dpor.virginia.gov/LicenseLookup", "DPOR; health professions at dhp.virginia.gov"),
        ]),
        StateEntry("Washington", [
            Link("Business Search", "https://ccfs.sos.wa.gov/#/BusinessSearch"),
            Link("Court Records", "https://dw.courts.wa.gov/", "Odyssey portal (37 counties) excludes King & Pierce"),
            Link("Inmate Search", "https://www.doc.wa.gov/information/inmate-search/default.aspx"),
            Link("Sex Offender Registry", "https://www.icrimewatch.net/index.php?AgencyID=54567", "WASPC aggregate (vendor-hosted)"),
            Link("Property Records", "https://publicrecords.netronline.com/state/WA", "County assessor/auditor directory (NETR)"),
            Link("License Lookup", "https://fortress.wa.gov/doh/providercredentialsearch/", "DOH health providers; others via DOL"),
        ]),
        StateEntry("West Virginia", [
            Link("Business Search", "https://apps.sos.wv.gov/business/corporations/"),
            Link("Court Records", "https://wvpass.courtswv.gov/", "WVPASS circuit courts; magistrate at mcrsearch.courtswv.gov"),
            Link("Inmate Search", "https://apps.wv.gov/ois/offendersearch/doc"),
            Link("Sex Offender Registry", "https://apps.wv.gov/StatePolice/SexOffender"),
            Link("Property Records", "https://mapwv.gov/parcel/", "Statewide property viewer"),
        ]),
        StateEntry("Wisconsin", [
            Link("Business Search", "https://apps.dfi.wi.gov/apps/CorpSearch/Advanced.aspx"),
            Link("Court Records", "https://wcca.wicourts.gov/", "CCAP — Circuit Court Access"),
            Link("Inmate Search", "https://appsdoc.wi.gov/lop/home/home"),
            Link("Sex Offender Registry", "https://appsdoc.wi.gov/public"),
            Link("Property Records", "https://maps.sco.wisc.edu/Parcels/", "Statewide parcel map; deeds county-level"),
            Link("License Lookup", "https://license.wi.gov/s/license-lookup"),
        ]),
        StateEntry("Wyoming", [
            Link("Business Search", "https://wyobiz.wyo.gov/Business/FilingSearch.aspx"),
            Link("Court Records", "https://www.wyocourts.gov/", "No free statewide portal — by county clerk of court"),
            Link("Inmate Search", "https://www.vinelink.com", "DOC has no .gov locator; uses VINE"),
            Link("Sex Offender Registry", "https://wsor.dci.wyo.gov/"),
            Link("Property Records", "https://publicrecords.netronline.com/state/WY", "County assessor/clerk directory (NETR)"),
        ]),
    ]
}
