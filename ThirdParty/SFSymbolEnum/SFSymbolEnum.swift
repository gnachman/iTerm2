import SwiftUI

public extension SFSymbol
{
    var name:String { return self.rawValue }

    @available(iOS 13.0, macOS 11.0, tvOS 13.0, visionOS 1.0, watchOS 6.0, *)
    var image:Image { return Image(systemName:self.rawValue) }
}

@available(iOS 13.0, macOS 11.0, tvOS 13.0, watchOS 6.0, *)
public extension Image {

    @available(iOS 13.0, macOS 11.0, tvOS 13.0, visionOS 1.0, watchOS 6.0, *)
    init(systemName symbol:SFSymbol){
        self = Image(systemName:symbol.name)
    }

    @available(iOS 13.0, macOS 11.0, tvOS 13.0, visionOS 1.0, watchOS 6.0, *)
    init(symbol:SFSymbol){
        self = Image(systemName:symbol.name)
    }
}

@available(iOS 14.0, macOS 11.0, tvOS 14.0, visionOS 1.0, watchOS 7.0, *)
public extension Label {
    init(_ title: LocalizedStringKey, systemImage symbol: SFSymbol) where Title == Text, Icon == Image
    {
         self = Label(title, systemImage:symbol.name)
    }

    init(_ title: LocalizedStringKey, symbol: SFSymbol)  where Title == Text, Icon == Image
    {
        self = Label(title, systemImage: symbol.name)
    }
}

public extension Button {
    @available(iOS 14.0, macOS 11.0, tvOS 14.0, visionOS 1.0, watchOS 7.0, *)
    init(_ titleKey: LocalizedStringKey, symbol: SFSymbol, action: @escaping () -> Void) where Label == SwiftUI.Label<Text,Image> {
        self = Button(action: action, label: {
            SwiftUI.Label(titleKey, symbol: symbol)
        })
    }
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, watchOS 8.0, *)
    init(_ titleKey: LocalizedStringKey, symbol: SFSymbol, role: ButtonRole?, action: @escaping () -> Void) where Label == SwiftUI.Label<Text,Image> {
        self = Button(titleKey, systemImage: symbol.name, role: role, action: action)
    }
}
