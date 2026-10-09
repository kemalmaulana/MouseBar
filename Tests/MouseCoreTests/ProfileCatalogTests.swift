import Testing
@testable import MouseCore

@Suite struct ProfileCatalogTests {
    @Test func loadsBothPrimeWirelessFamilies() throws {
        let catalog = try ProfileCatalog.load()
        #expect(catalog.rivalcfgVersion == "4.17.0")
        #expect(catalog.families.map(\.id) == primeFamilyIDs)
    }

    @Test func matchesDongleToWirelessFamily() throws {
        let catalog = try ProfileCatalog.load()
        let match = try #require(catalog.match(vendorID: 0x1038, productID: 0x1848))
        #expect(match.family.id == "prime_wireless_wireless")
        #expect(match.model.name.hasPrefix("SteelSeries Prime Mini Wireless"))
        #expect(match.model.endpoint == 3)
        #expect(match.model.mouse == "prime_mini_wireless")
        #expect(match.model.isWireless)
    }

    @Test func matchesCableToWiredFamilyWithSameMouseGroup() throws {
        let catalog = try ProfileCatalog.load()
        let match = try #require(catalog.match(vendorID: 0x1038, productID: 0x184A))
        #expect(match.family.id == "prime_wireless_wired")
        #expect(match.model.mouse == "prime_mini_wireless")
        #expect(!match.model.isWireless)
    }

    @Test func unknownProductDoesNotMatch() throws {
        let catalog = try ProfileCatalog.load()
        #expect(catalog.match(vendorID: 0x1038, productID: 0xFFFF) == nil)
        #expect(catalog.match(vendorID: 0x046D, productID: 0x1848) == nil)
    }

    @Test func wiredFamilyDeclaresTheSevenRivalcfgSettingsInOrder() throws {
        let catalog = try ProfileCatalog.load()
        let family = try #require(catalog.families.first { $0.id == "prime_wireless_wired" })
        #expect(family.settings.map(\.key) == [
            "sensitivity", "polling_rate", "color", "buttons_mapping",
            "sleep_timer", "dim_timer", "default_lighting",
        ])
        #expect(family.saveCommand?.command == [0x11, 0x00])
        #expect(family.battery?.command == [0x92])
    }

    @Test func wirelessFamilyCommandsCarryTheWirelessFlagAndReadback() throws {
        let catalog = try ProfileCatalog.load()
        let family = try #require(catalog.families.first { $0.id == "prime_wireless_wireless" })
        #expect(family.setting("polling_rate")?.command == [0x6B])
        #expect(family.setting("polling_rate")?.readbackLength == 64)
        #expect(family.saveCommand?.command == [0x51, 0x00])
        #expect(family.battery?.command == [0xD2])
    }

    @Test func colorIsNotPersistedOnDeviceButOtherSettingsAre() throws {
        let catalog = try ProfileCatalog.load()
        let family = try #require(catalog.families.first { $0.id == "prime_wireless_wired" })
        #expect(family.setting("color")?.persistsOnDevice == false)
        #expect(family.setting("polling_rate")?.persistsOnDevice == true)
    }

    @Test func layoutsResolveAliasesAndLowercase() throws {
        let layouts = try ButtonLayouts.load()
        #expect(layouts.multimedia["playpause"] == 0xCD)
        #expect(layouts.multimedia["vol+"] == 0xE9)
        #expect(layouts.keyboard["a"] == 0x04)
        #expect(layouts.multimediaKeys.contains("PlayPause"))
    }
}
