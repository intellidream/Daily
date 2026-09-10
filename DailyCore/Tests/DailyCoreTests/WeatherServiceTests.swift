import XCTest
@testable import DailyCore

final class WeatherServiceTests: XCTestCase {

    func testDecodeWeatherResponse() throws {
        let json = """
        {
            "coord": { "lon": 26.1025, "lat": 44.4268 },
            "weather": [
                { "id": 800, "main": "Clear", "description": "clear sky", "icon": "01d" }
            ],
            "base": "stations",
            "main": {
                "temp": 24.5,
                "feels_like": 24.1,
                "temp_min": 23.0,
                "temp_max": 26.0,
                "pressure": 1013,
                "humidity": 45
            },
            "visibility": 10000,
            "wind": { "speed": 3.6, "deg": 180 },
            "clouds": { "all": 0 },
            "dt": 1726000000,
            "sys": { "country": "RO", "sunrise": 1725940000, "sunset": 1725988000 },
            "timezone": 10800,
            "id": 683506,
            "name": "Bucharest",
            "cod": 200
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(WeatherResponse.self, from: json)
        XCTAssertEqual(response.name, "Bucharest")
        XCTAssertEqual(response.main.temp, 24.5)
        XCTAssertEqual(response.main.humidity, 45)
        XCTAssertEqual(response.weather.first?.description, "clear sky")
        XCTAssertEqual(response.wind?.cardinalDirection, "S")
    }

    func testDecodeForecastResponse() throws {
        let json = """
        {
            "cod": "200",
            "message": 0,
            "cnt": 2,
            "list": [
                {
                    "dt": 1726000000,
                    "main": {
                        "temp": 22.0,
                        "feels_like": 21.8,
                        "temp_min": 20.0,
                        "temp_max": 23.0,
                        "pressure": 1015,
                        "humidity": 50
                    },
                    "weather": [
                        { "id": 500, "main": "Rain", "description": "light rain", "icon": "10d" }
                    ],
                    "clouds": { "all": 75 },
                    "wind": { "speed": 4.1, "deg": 90 },
                    "visibility": 9000,
                    "pop": 0.45,
                    "dt_txt": "2026-09-10 12:00:00"
                }
            ],
            "city": {
                "id": 683506,
                "name": "Bucharest",
                "coord": { "lat": 44.4268, "lon": 26.1025 },
                "country": "RO",
                "population": 1877155,
                "timezone": 10800,
                "sunrise": 1725940000,
                "sunset": 1725988000
            }
        }
        """.data(using: .utf8)!

        let forecast = try JSONDecoder().decode(ForecastResponse.self, from: json)
        XCTAssertEqual(forecast.list.count, 1)
        XCTAssertEqual(forecast.list.first?.main.temp, 22.0)
        XCTAssertEqual(forecast.list.first?.pop, 0.45)
        XCTAssertEqual(forecast.city?.name, "Bucharest")
    }

    func testLocationSuggestionDecoding() throws {
        let json = """
        [
            {
                "name": "London",
                "lat": 51.5073,
                "lon": -0.1276,
                "country": "GB",
                "state": "England"
            }
        ]
        """.data(using: .utf8)!

        let suggestions = try JSONDecoder().decode([LocationSuggestion].self, from: json)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.displayName, "London, England, GB")
    }

    func testWeatherConditionHelper() {
        XCTAssertEqual(WeatherConditionHelper.sfSymbol(for: "01d"), "sun.max.fill")
        XCTAssertEqual(WeatherConditionHelper.sfSymbol(for: "10d"), "cloud.sun.rain.fill")
        XCTAssertEqual(WeatherConditionHelper.sfSymbol(for: "13d"), "snowflake")
        XCTAssertEqual(WeatherConditionHelper.sfSymbol(for: "11n"), "cloud.bolt.rain.fill")
    }

    func testWindCardinalDirections() {
        let northWind = Wind(speed: 5.0, deg: 0)
        let eastWind = Wind(speed: 5.0, deg: 90)
        let southWind = Wind(speed: 5.0, deg: 180)
        let westWind = Wind(speed: 5.0, deg: 270)

        XCTAssertEqual(northWind.cardinalDirection, "N")
        XCTAssertEqual(eastWind.cardinalDirection, "E")
        XCTAssertEqual(southWind.cardinalDirection, "S")
        XCTAssertEqual(westWind.cardinalDirection, "W")
    }
}
