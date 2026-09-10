import Foundation

// MARK: - OpenWeatherMap Current Weather Response

public struct WeatherResponse: Codable, Sendable {
    public let coord: Coord?
    public let weather: [WeatherDescription]
    public let main: MainWeather
    public let visibility: Int?
    public let wind: Wind?
    public let clouds: Clouds?
    public let dt: Int
    public let sys: Sys?
    public let timezone: Int?
    public let id: Int?
    public let name: String
    public let cod: Int?

    public init(
        coord: Coord? = nil,
        weather: [WeatherDescription] = [],
        main: MainWeather,
        visibility: Int? = nil,
        wind: Wind? = nil,
        clouds: Clouds? = nil,
        dt: Int = Int(Date().timeIntervalSince1970),
        sys: Sys? = nil,
        timezone: Int? = nil,
        id: Int? = nil,
        name: String = "",
        cod: Int? = nil
    ) {
        self.coord = coord
        self.weather = weather
        self.main = main
        self.visibility = visibility
        self.wind = wind
        self.clouds = clouds
        self.dt = dt
        self.sys = sys
        self.timezone = timezone
        self.id = id
        self.name = name
        self.cod = cod
    }
}

// MARK: - OpenWeatherMap 5-Day / 3-Hour Forecast Response

public struct ForecastResponse: Codable, Sendable {
    public let cod: String?
    public let message: Int?
    public let cnt: Int?
    public let list: [ForecastItem]
    public let city: City?

    public init(
        cod: String? = nil,
        message: Int? = nil,
        cnt: Int? = nil,
        list: [ForecastItem] = [],
        city: City? = nil
    ) {
        self.cod = cod
        self.message = message
        self.cnt = cnt
        self.list = list
        self.city = city
    }
}

public struct ForecastItem: Codable, Sendable, Identifiable {
    public var id: Int { dt }
    public let dt: Int
    public let main: MainWeather
    public let weather: [WeatherDescription]
    public let clouds: Clouds?
    public let wind: Wind?
    public let visibility: Int?
    public let pop: Double? // Probability of precipitation (0.0 to 1.0)
    public let dtTxt: String?

    enum CodingKeys: String, CodingKey {
        case dt, main, weather, clouds, wind, visibility, pop
        case dtTxt = "dt_txt"
    }

    public init(
        dt: Int,
        main: MainWeather,
        weather: [WeatherDescription],
        clouds: Clouds? = nil,
        wind: Wind? = nil,
        visibility: Int? = nil,
        pop: Double? = nil,
        dtTxt: String? = nil
    ) {
        self.dt = dt
        self.main = main
        self.weather = weather
        self.clouds = clouds
        self.wind = wind
        self.visibility = visibility
        self.pop = pop
        self.dtTxt = dtTxt
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(dt))
    }
}

// MARK: - Component Models

public struct Coord: Codable, Sendable {
    public let lon: Double
    public let lat: Double

    public init(lon: Double, lat: Double) {
        self.lon = lon
        self.lat = lat
    }
}

public struct WeatherDescription: Codable, Sendable, Identifiable {
    public let id: Int
    public let main: String
    public let description: String
    public let icon: String

    public init(id: Int, main: String, description: String, icon: String) {
        self.id = id
        self.main = main
        self.description = description
        self.icon = icon
    }
}

public struct MainWeather: Codable, Sendable {
    public let temp: Double
    public let feelsLike: Double
    public let tempMin: Double
    public let tempMax: Double
    public let pressure: Int
    public let humidity: Int

    enum CodingKeys: String, CodingKey {
        case temp
        case feelsLike = "feels_like"
        case tempMin = "temp_min"
        case tempMax = "temp_max"
        case pressure
        case humidity
    }

    public init(
        temp: Double,
        feelsLike: Double,
        tempMin: Double,
        tempMax: Double,
        pressure: Int,
        humidity: Int
    ) {
        self.temp = temp
        self.feelsLike = feelsLike
        self.tempMin = tempMin
        self.tempMax = tempMax
        self.pressure = pressure
        self.humidity = humidity
    }
}

public struct Wind: Codable, Sendable {
    public let speed: Double
    public let deg: Int?

    public init(speed: Double, deg: Int? = nil) {
        self.speed = speed
        self.deg = deg
    }

    public var cardinalDirection: String {
        guard let deg = deg else { return "N/A" }
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((Double(deg) + 11.25) / 22.5) % 16
        return directions[index]
    }
}

public struct Clouds: Codable, Sendable {
    public let all: Int?

    public init(all: Int? = nil) {
        self.all = all
    }
}

public struct Sys: Codable, Sendable {
    public let country: String?
    public let sunrise: Int?
    public let sunset: Int?

    public init(country: String? = nil, sunrise: Int? = nil, sunset: Int? = nil) {
        self.country = country
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

public struct City: Codable, Sendable {
    public let id: Int?
    public let name: String?
    public let coord: Coord?
    public let country: String?
    public let timezone: Int?
    public let sunrise: Int?
    public let sunset: Int?

    public init(
        id: Int? = nil,
        name: String? = nil,
        coord: Coord? = nil,
        country: String? = nil,
        timezone: Int? = nil,
        sunrise: Int? = nil,
        sunset: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.coord = coord
        self.country = country
        self.timezone = timezone
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

// MARK: - Direct Geocoding Models

public struct LocationSuggestion: Codable, Sendable, Identifiable, Hashable {
    public var id: String { "\(lat)_\(lon)_\(name)" }
    public let name: String
    public let state: String?
    public let country: String?
    public let lat: Double
    public let lon: Double

    public init(name: String, state: String? = nil, country: String? = nil, lat: Double, lon: Double) {
        self.name = name
        self.state = state
        self.country = country
        self.lat = lat
        self.lon = lon
    }

    public var displayName: String {
        var parts: [String] = [name]
        if let state = state, !state.isEmpty {
            parts.append(state)
        }
        if let country = country, !country.isEmpty {
            parts.append(country)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - IP Geolocation (freeipapi.com)

public struct IpLocationResponse: Codable, Sendable {
    public let latitude: Double?
    public let longitude: Double?
    public let cityName: String?
    public let countryName: String?

    public init(latitude: Double? = nil, longitude: Double? = nil, cityName: String? = nil, countryName: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.cityName = cityName
        self.countryName = countryName
    }
}

// MARK: - Daily Forecast Aggregation (for 5-day view)

public struct DailyForecastSummary: Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let dayName: String
    public let dateFormatted: String
    public let tempMin: Double
    public let tempMax: Double
    public let iconCode: String
    public let sfSymbolName: String
    public let conditionText: String
    public let popMax: Double // 0.0 to 1.0

    public init(
        id: String,
        date: Date,
        dayName: String,
        dateFormatted: String,
        tempMin: Double,
        tempMax: Double,
        iconCode: String,
        sfSymbolName: String,
        conditionText: String,
        popMax: Double
    ) {
        self.id = id
        self.date = date
        self.dayName = dayName
        self.dateFormatted = dateFormatted
        self.tempMin = tempMin
        self.tempMax = tempMax
        self.iconCode = iconCode
        self.sfSymbolName = sfSymbolName
        self.conditionText = conditionText
        self.popMax = popMax
    }
}

// MARK: - SF Symbol & Weather Condition Helper

public enum WeatherConditionHelper {
    /// Maps OpenWeatherMap icon code (e.g. "01d", "10n") or weather ID to native SF Symbols
    public static func sfSymbol(for iconCode: String) -> String {
        switch iconCode {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.stars.fill"
        case "02d": return "cloud.sun.fill"
        case "02n": return "cloud.moon.fill"
        case "03d", "03n": return "cloud.fill"
        case "04d", "04n": return "smoke.fill"
        case "09d", "09n": return "cloud.drizzle.fill"
        case "10d": return "cloud.sun.rain.fill"
        case "10n": return "cloud.moon.rain.fill"
        case "11d", "11n": return "cloud.bolt.rain.fill"
        case "13d", "13n": return "snowflake"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "cloud.sun.fill"
        }
    }

    /// Primary accent color hex for the weather condition
    public static func conditionColorHex(for iconCode: String) -> String {
        switch iconCode {
        case "01d": return "#FFD166" // Warm Sun
        case "01n": return "#A0B2C6" // Moon silver
        case "02d": return "#FFE082" // Sun with cloud
        case "02n": return "#78909C"
        case "03d", "03n", "04d", "04n": return "#90A4AE" // Cloud gray
        case "09d", "09n", "10d", "10n": return "#4A9EFF" // Rain blue
        case "11d", "11n": return "#FFB74D" // Lightning amber
        case "13d", "13n": return "#80DEEA" // Snow cyan
        case "50d", "50n": return "#B0BEC5" // Fog
        default: return "#00E5FF"
        }
    }
}
