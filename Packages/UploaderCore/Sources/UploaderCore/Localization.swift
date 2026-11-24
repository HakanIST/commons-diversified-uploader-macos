import Foundation

/// Çekirdek kitaplığın kullanıcıya gösterilen metinleri (kaynak dil Türkçe, çeviriler paket kaynaklarında).
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
