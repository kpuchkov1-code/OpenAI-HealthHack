//
//  FoodLogging.swift
//  AmberAI
//
//  The non-UI half of food logging: the four ways to turn a meal into a FoodEntry.
//  Two rungs read real label data (barcode + name search, via Open Food Facts); two
//  rungs are Amber's estimate (a description, or a photo) and are flagged as such so a
//  guess never renders like a fact. Kept out of the views so it stays testable, the same
//  way Food.swift keeps the food maths out of the UI.
//

import Foundation

/// A resolved-but-unsaved food. Any of the four paths produces one of these; the user
/// confirms it (and picks the day) before it becomes a persisted FoodEntry.
struct FoodDraft: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var source: FoodSource
    var nutrition: FoodNutrition?
    var barcode: String?
    var provenance: String
    /// True for the estimate rungs (description, photo). A guess must not look like a label.
    var estimated: Bool?
    var note: String?
}

/// Next `fe-NNN` id, mirroring nextFactId's scheme so seeded and logged entries share a
/// numbering.
func nextFoodId(_ entries: [FoodEntry]) -> String {
    let nums = entries.compactMap { Int($0.id.replacingOccurrences(of: "fe-", with: "")) }
    return "fe-" + String(format: "%03d", (nums.max() ?? 0) + 1)
}

// MARK: - Open Food Facts

/// The public Open Food Facts database. No key required; they only ask for an
/// identifying User-Agent. Barcode lookup is exact; search is by product name.
enum OpenFoodFacts {
    private static let agent = "AmberAI/1.0 (health companion demo)"

    /// Exact lookup by barcode (EAN/UPC). Returns nil when the code is not in the database.
    static func lookup(barcode: String) async throws -> FoodDraft? {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,nutriments,code")!
        let obj = try await getJSON(url)
        guard (obj["status"] as? Int) == 1, let product = obj["product"] as? [String: Any] else {
            return nil
        }
        return draft(from: product, source: .barcode, fallbackCode: code)
    }

    /// Name search. Returns the products that carry at least a name, best-effort ordered
    /// as Open Food Facts returns them.
    static func search(_ query: String) async throws -> [FoodDraft] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(q)&search_simple=1&action=process&json=1&page_size=20&fields=product_name,brands,nutriments,code")!
        let obj = try await getJSON(url)
        let products = (obj["products"] as? [[String: Any]]) ?? []
        return products.compactMap { draft(from: $0, source: .search, fallbackCode: nil) }
    }

    // MARK: helpers

    private static func getJSON(_ url: URL) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.setValue(agent, forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw RunwareError(message: "Could not reach Open Food Facts.", detail: String(describing: error))
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RunwareError(message: "Open Food Facts \(http.statusCode)", detail: nil)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RunwareError(message: "Open Food Facts returned an unexpected response.", detail: nil)
        }
        return obj
    }

    private static func draft(from product: [String: Any], source: FoodSource, fallbackCode: String?) -> FoodDraft? {
        let name = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        let brand = (product["brands"] as? String)?
            .split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let label = (brand?.isEmpty == false) ? "\(name), \(brand!)" : name
        let code = (product["code"] as? String)?.nilIfEmpty ?? fallbackCode
        let prov = code.map { "Open Food Facts · \($0)" } ?? "Open Food Facts"
        return FoodDraft(label: label, source: source,
                         nutrition: nutrition(from: product["nutriments"] as? [String: Any]),
                         barcode: code, provenance: prov, estimated: nil, note: nil)
    }

    /// Open Food Facts nutriments are per 100 g. Values arrive as numbers or strings.
    private static func nutrition(from n: [String: Any]?) -> FoodNutrition? {
        guard let n else { return nil }
        let kcal = looseNumber(n["energy-kcal_100g"])
        let protein = looseNumber(n["proteins_100g"])
        let carbs = looseNumber(n["carbohydrates_100g"])
        let fat = looseNumber(n["fat_100g"])
        let fibre = looseNumber(n["fiber_100g"])
        if kcal == nil && protein == nil && carbs == nil && fat == nil && fibre == nil { return nil }
        return FoodNutrition(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat, fibreG: fibre, basis: "per_100g")
    }
}

// MARK: - AI estimation

/// The two model-backed rungs. Both return an estimate for the portion described or
/// shown, marked `estimated`, never a label's stated truth.
enum FoodAI {
    private static let system = """
    You estimate the nutrition of a single meal or food for a personal food log. \
    Reply with ONLY a JSON object and nothing else, of the form:
    {"label": "short name of the food", "kcal": number, "proteinG": number, "carbsG": number, "fatG": number, "fibreG": number}
    Estimate for the portion described or shown, not per 100g. Always give the full macro \
    breakdown — kcal, protein, carbs and fat — as your single best estimate, not just \
    calories; include fibre too when you reasonably can. Omit a field only if you genuinely \
    cannot guess it. Numbers must be bare numbers with no units, ranges, or commentary.
    """

    static func fromDescription(_ text: String) async throws -> FoodDraft {
        let raw = try await Runware.text(
            system: system,
            messages: [RunwareMessage(role: "user", content: "The food: \(text)")],
            model: RunwareConfig.foodModel,
            temperature: 0.2, maxTokens: 300)
        return try parse(raw, fallbackLabel: text, source: .described, provenance: "You described it")
    }

    static func fromImage(_ jpeg: Data) async throws -> FoodDraft {
        let raw = try await Runware.visionText(
            system: system,
            prompt: "Identify the food in this photo and estimate its nutrition for the portion shown.",
            imageData: jpeg, model: RunwareConfig.foodModel,
            temperature: 0.2, maxTokens: 300)
        return try parse(raw, fallbackLabel: "Photo of a meal", source: .photo, provenance: "Estimated from a photo")
    }

    private static func parse(_ raw: String, fallbackLabel: String, source: FoodSource, provenance: String) throws -> FoodDraft {
        guard let obj = parseJsonLoose(raw) else {
            throw RunwareError(message: "Amber could not read that back as an estimate.", detail: String(raw.prefix(200)))
        }
        let label = (obj["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackLabel
        let nutrition = FoodNutrition(
            kcal: looseNumber(obj["kcal"]), proteinG: looseNumber(obj["proteinG"]),
            carbsG: looseNumber(obj["carbsG"]), fatG: looseNumber(obj["fatG"]),
            fibreG: looseNumber(obj["fibreG"]), basis: "per_serving")
        return FoodDraft(label: label, source: source, nutrition: nutrition,
                         barcode: nil, provenance: provenance, estimated: true, note: nil)
    }
}

// MARK: - Shared parsing

/// Reads a number that may have arrived as Double, Int, NSNumber, or a numeric String.
func looseNumber(_ value: Any?) -> Double? {
    switch value {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
    default: return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
