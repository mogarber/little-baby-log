import Testing
import Foundation
@testable import BabyLogKit

struct DeepLinkTests {
    let baby = UUID(uuidString: "6B29FC40-CA47-1067-B31D-00DD010662DA")!

    @Test func parsesDocumentedForms() {
        #expect(DeepLink(url: URL(string: "littlebabylog://log/bottle")!) == .log(.bottle, babyID: nil))
        #expect(DeepLink(url: URL(string: "littlebabylog://log/bottle?baby=\(baby.uuidString)")!) == .log(.bottle, babyID: baby))
        #expect(DeepLink(url: URL(string: "littlebabylog://nursing?baby=\(baby.uuidString)")!) == .nursing(babyID: baby))
        #expect(DeepLink(url: URL(string: "littlebabylog://today")!) == .today(babyID: nil))
        #expect(DeepLink(url: URL(string: "LittleBabyLog://Log/Solids")!) == .log(.solids, babyID: nil))
    }

    @Test func rejectsEverythingElse() {
        #expect(DeepLink(url: URL(string: "https://example.com/log/bottle")!) == nil)
        #expect(DeepLink(url: URL(string: "littlebabylog://log")!) == nil)
        #expect(DeepLink(url: URL(string: "littlebabylog://log/teleport")!) == nil)
        #expect(DeepLink(url: URL(string: "littlebabylog://settings")!) == nil)
    }

    @Test func badBabyIDIsIgnored() {
        #expect(DeepLink(url: URL(string: "littlebabylog://today?baby=nope")!) == .today(babyID: nil))
    }

    @Test func roundTrip() {
        for kind in EventKind.allCases {
            for id in [baby, nil] {
                let link = DeepLink.log(kind, babyID: id)
                #expect(DeepLink(url: link.url) == link)
            }
        }
        for link in [DeepLink.nursing(babyID: baby), .nursing(babyID: nil), .today(babyID: baby), .today(babyID: nil)] {
            #expect(DeepLink(url: link.url) == link)
        }
        #expect(DeepLink.log(.bottle, babyID: nil).url.absoluteString == "littlebabylog://log/bottle")
    }
}
