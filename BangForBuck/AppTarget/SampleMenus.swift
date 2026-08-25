import Foundation

/// Bundled sample menus (transcribed OCR-style lines) so the app shows real rankings without a
/// camera yet. In the real capture flow these lines come from Apple Vision on your photo; here
/// they stand in so you can see the value engine end-to-end.
struct SampleMenu: Identifiable {
    let id = UUID()
    let name: String
    let lines: [String]
}

enum SampleMenus {
    static let all: [SampleMenu] = [
        SampleMenu(name: "Cocktail bar", lines: [
            "COCKTAILS",
            "Sunset Tea $8",
            "Lemon Vodka, Triple Sec, and Sweet Tea",
            "Peach Tree Punch $9",
            "The Best Margarita $13",
            "FROZEN COCKTAILS",
            "Bushwacker $10",
            "Mango Paradise $8",
            "SELTZERS",
            "High Noon $9",
            "White Claw $8",
            "IMPORTS",
            "Corona $5",
            "Modelo $5",
            "Stella Artois $5",
            "MOCKTAILS",
            "Virgin Mojito $7",
        ]),
        SampleMenu(name: "Beer list", lines: [
            "BOTTLES",
            "Bud Light $4",
            "Coors Light $4",
            "Guinness $6",
            "Modelo Especial $6",
            "Corona Extra $6",
            "Hazy IPA $7",
            "Heineken 0.0 $5",
            "NON-ALCOHOLIC",
            "Athletic Run Wild $6",
        ]),
        SampleMenu(name: "Wine list", lines: [
            "WINE",
            "Cabernet $12",
            "Chardonnay $11",
            "Prosecco $10",
            "Moscato $9",
            "Pinot Noir $13",
            "Riesling $10",
        ]),
    ]
}
