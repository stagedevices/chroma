import SwiftUI

enum ChromaTypography {
    static var body: Font {
        .custom("Oswald-Regular", size: 18, relativeTo: .body)
    }

    static var bodySecondary: Font {
        .custom("Oswald-Light", size: 17, relativeTo: .subheadline)
    }

    static var hero: Font {
        .custom("Oswald-Bold", size: 52, relativeTo: .largeTitle)
    }

    static var overline: Font {
        .custom("Oswald-Medium", size: 13, relativeTo: .caption)
    }

    static var title: Font {
        .custom("Oswald-SemiBold", size: 34, relativeTo: .title2)
    }

    static var subtitle: Font {
        .custom("Oswald-Medium", size: 24, relativeTo: .title3)
    }

    static var action: Font {
        .custom("Oswald-Medium", size: 18, relativeTo: .subheadline)
    }

    static var panelTitle: Font {
        .custom("Oswald-SemiBold", size: 28, relativeTo: .title3)
    }

    static var metric: Font {
        .custom("Oswald-Regular", size: 16, relativeTo: .caption)
    }

    static var sheetRowTitle: Font {
        .custom("Oswald-Medium", size: 21, relativeTo: .headline)
    }

    static var sheetSectionHeader: Font {
        .custom("Oswald-Medium", size: 13, relativeTo: .caption)
    }
}
