import SwiftUI

struct CatalogFilters: Equatable, Sendable {
    enum Sort: String, CaseIterable, Identifiable, Sendable {
        case recent = "Adicionados recentemente"
        case az = "Nome (A–Z)"
        case rating = "Melhor avaliados"
        case year = "Lançamento mais novo"
        var id: String { rawValue }
    }

    var sort: Sort = .recent
    var minRating: Double = 0
    var decade: Int? = nil
    var genre: String? = nil

    var activeCount: Int {
        (sort != .recent ? 1 : 0) + (minRating > 0 ? 1 : 0) + (decade != nil ? 1 : 0) + (genre != nil ? 1 : 0)
    }
}

/// Filtragem fora da thread principal, para listas com dezenas de milhares de itens.
enum CatalogEngine {
    static let favoritesId = "__favorites"

    static func run(_ items: [MediaItem], category: String?, favorites: Set<String>,
                    query: String, filters f: CatalogFilters) -> [MediaItem] {
        let q = TextUtil.searchKey(query.trimmingCharacters(in: .whitespacesAndNewlines))
        var out = items.filter { item in
            if let category {
                if category == favoritesId {
                    if !favorites.contains(item.favKey) { return false }
                } else if item.categoryId != category {
                    return false
                }
            }
            if !q.isEmpty && !item.searchKey.contains(q) { return false }
            if f.minRating > 0 && (item.rating ?? 0) < f.minRating { return false }
            if let d = f.decade {
                guard let y = item.year else { return false }
                if d <= 1980 { if y >= 1990 { return false } }
                else if y < d || y >= d + 10 { return false }
            }
            if let g = f.genre, !item.genres.contains(g) { return false }
            return true
        }
        switch f.sort {
        case .recent: out.sort { $0.added > $1.added }
        case .az: out.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .rating: out.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .year: out.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        }
        return out
    }
}

struct FilterSheet: View {
    @Binding var filters: CatalogFilters
    let genres: [String]
    @Environment(\.dismiss) private var dismiss

    private let ratings: [Double] = [0, 5, 6, 7, 8]
    private let decades: [Int] = [2020, 2010, 2000, 1990, 1980]

    var body: some View {
        NavigationStack {
            Form {
                Section("Ordenar por") {
                    Picker("Ordenar por", selection: $filters.sort) {
                        ForEach(CatalogFilters.Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Nota mínima") {
                    Picker("Nota mínima", selection: $filters.minRating) {
                        ForEach(ratings, id: \.self) { r in
                            Text(r == 0 ? "Todas" : "\(Int(r))+").tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Época") {
                    Picker("Década", selection: $filters.decade) {
                        Text("Qualquer").tag(Int?.none)
                        ForEach(decades, id: \.self) { d in
                            Text(d <= 1980 ? "Antes de 1990" : "Anos \(String(d))").tag(Int?.some(d))
                        }
                    }
                }

                if !genres.isEmpty {
                    Section("Gênero") {
                        Picker("Gênero", selection: $filters.genre) {
                            Text("Todos").tag(String?.none)
                            ForEach(genres, id: \.self) { g in
                                Text(g).tag(String?.some(g))
                            }
                        }
                    }
                }

                Section {
                    Button("Limpar filtros", role: .destructive) { filters = CatalogFilters() }
                        .disabled(filters.activeCount == 0)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Aplicar") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
