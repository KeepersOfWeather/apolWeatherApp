//
//  ApiFriend.swift
//  WeatherApp
//
//  Created by Camiel Verdult on 18/12/2021.
//

import Foundation

class ApiFriend: ObservableObject {
    @Published var weatherData: [WeatherData] = []
    var parsedPoints: [PointParsed] = []
    var parsedLocations: [Location] = []

    func getLocations(blocker: DispatchSemaphore) -> Void {
        guard let url = URL(string: "https://keepersofweather.nl/api/devices/locations") else { fatalError("Missing URL") }

        let urlRequest = URLRequest(url: url)

        let dataTask = URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
            if let error = error {
                print("Request error: \(error)")
                return
            }
            
            print("Asking API for locations...")

            guard let response = response as? HTTPURLResponse else { return }

            if response.statusCode == 200 {
                
                print("Got locations from API, parsing...")
                
                guard let data = data else { return }
                
                print("Decoding location from JSON...")
                DispatchQueue.global().async {
                    do {
                        let decodedLocations = try JSONDecoder().decode([Location].self, from: data)
                        self.parsedLocations = decodedLocations
                        blocker.signal()
                    } catch let error {
                        print("Error decoding locations: ", error)
                    }
                    
                    print("Parsed \(self.parsedPoints.count) locations")
                }
            }
        }
        
        dataTask.resume()
        blocker.wait()
    }

/*
        [
            {
                "City" : "Enschede",
                "deviceId: py-saxion,
                "deviceIndex" : 1
            },
            ...
        ]
    */
    
    struct City: Identifiable {
        let id: UUID
        let name: String
    }
    
    func getCities() -> [City] {
        /// This functions will find all distinct cities in our weather points
        // Figure out the name of our cities
        var locations: [String] = []
        
        for weatherDatum in weatherData {
            if (!locations.contains(weatherDatum.metadata.LocationData.City)) {
                locations.append(weatherDatum.metadata.LocationData.City)
            }
        }
        
        // Put our city names into city object, which are identifiable
        // because swift likes it to be this way
        var cities: [City] = []
        
        for cityName in locations {
            cities.append(City(id: UUID(), name: cityName))
        }
        
        return cities
    }
    
    func getWeatherpoints(forCity: City) -> [WeatherData] {
        /// This function returns all weatherpoints in a parsed city
        var weatherPoints: [WeatherData] = []
        
        for weatherDatum in weatherData {
            if (weatherDatum.metadata.LocationData.City == forCity.name) {
                weatherPoints.append(weatherDatum)
            }
        }
        
        return weatherPoints
    }
    
    func getTemperatures(forCity: City) -> [Double] {
        var temperatures: [Double] = []
        
        for weatherDatum in self.getWeatherpoints(forCity: forCity) {
            temperatures.append(weatherDatum.sensorData.temperature)
        }
        
        return temperatures
    }

    func getWeatherpoints(blocker: DispatchSemaphore) -> Void {
        /// This function will get the latest 24 hour of weatherpoints from the API and parse the JSON to PointParsed classes
        guard let url = URL(string: "https://keepersofweather.nl/api") else { fatalError("Missing URL") }

        let urlRequest = URLRequest(url: url)

        let dataTask = URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
            if let error = error {
                print("Request error: ", error)
                return
            }

            guard let response = response as? HTTPURLResponse else { return }

            if response.statusCode == 200 {
                
                print("Got weatherpoints")
                
                guard let data = data else { return }
                print("Decoding weatherpoints from JSON...")
                DispatchQueue.global().async {
                    do {
                        let decodedWeatherpoints = try JSONDecoder().decode([PointParsed].self, from: data)
                        self.parsedPoints = decodedWeatherpoints
                        blocker.signal()
                    } catch let error {
                        print("Error decoding weaterpoints: ", error)
                    }
                    
                    print("Parsed \(self.parsedPoints.count) weather points")
                    
                    
                }
            }
        }
        
        print("Resuming API JSON parsing task...")

        dataTask.resume()
        blocker.wait()
    }
    
    func sortWeatherpoints() -> Void {
        var convertedArray: [Date] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd hh:mm:ss"

        for dat in self.parsedPoints {
            let date = dateFormatter.date(from: dat.metadata.utcTimeStamp.replacingOccurrences(of: "T", with: " "))
            
            if let date = date {
                convertedArray.append(date)
            }
        }

        let ready = convertedArray.sorted(by: { $0.compare($1) == .orderedDescending })

        print(ready)
    }
    
    func formatTimeString(timeString: String) -> String {
        let split = timeString.split(separator: "T")
        
        let timePart = split[0].split(separator: "-")
        
        return "\(split[1]) \(timePart[2])-\(timePart[1])-\(timePart[0])"
    }
    
    func initialise() -> Void {
        
        let blocker = DispatchSemaphore(value: 0)
        
        self.getWeatherpoints(blocker: blocker)
        self.getLocations(blocker: blocker)
        self.sortWeatherpoints()

        print("Rebuilding to WeatherData with unique id...")

        for var point in self.parsedPoints {
            
            point.metadata.utcTimeStamp = self.formatTimeString(timeString: point.metadata.utcTimeStamp)
            
            var locationForWeatherpoint = Location(City: "Earth", deviceID: "lht-mars", deviceNumber: 0)
            
            for location in self.parsedLocations {
                if (location.deviceID == point.metadata.deviceID) {
                    locationForWeatherpoint = location
                }
            }
            
            let metadataWithLocation = MetadataExtra(utcTimeStamp: point.metadata.utcTimeStamp, deviceID: point.metadata.deviceID, applicationID: point.metadata.applicationID, gatewayID: point.metadata.gatewayID, LocationData: locationForWeatherpoint)
            
            let newPoint = WeatherData(id: UUID(), metadata: metadataWithLocation, positional: point.positional, sensorData: point.sensorData, transmissionalData: point.transmissionalData)
            
            self.weatherData.append(newPoint)
        }

    }
    
    func dateTimeChangeFormat(str stringWithDate: String, inDateFormat: String, outDateFormat: String) -> String {
        let inFormatter = DateFormatter()
        inFormatter.locale = Locale(identifier: "en_US_POSIX")
        inFormatter.dateFormat = inDateFormat

        let outFormatter = DateFormatter()
        outFormatter.locale = Locale(identifier: "en_US_POSIX")
        outFormatter.dateFormat = outDateFormat

        let inStr = stringWithDate
        let date = inFormatter.date(from: inStr)!
        return outFormatter.string(from: date)
    }

}

struct Location: Codable {
    let City: String
    let deviceID: String
    let deviceNumber: Int
}

struct WeatherData: Identifiable {
    let id: UUID
    let metadata: MetadataExtra
    let positional: Positional
    let sensorData: SensorData
    let transmissionalData: TransmissionalData
}

struct PointParsed: Codable {
    var metadata: Metadata
    let positional: Positional
    let sensorData: SensorData
    let transmissionalData: TransmissionalData
}

struct MetadataExtra: Codable {
    let utcTimeStamp, deviceID, applicationID, gatewayID: String
    let LocationData: Location
}

// MARK: - Metadata
struct Metadata: Codable {
    var utcTimeStamp, deviceID, applicationID, gatewayID: String
}

// MARK: - Positional
struct Positional: Codable {
    let latitude, longitude: Double?
    let altitude: Int?
}

// MARK: - SensorData
struct SensorData: Codable {
    let lightLogscale: Int?
    let lightLux: Int?
    let temperature: Double
    let humidity: Float?
    let pressure: Float?
    let batteryStatus: Int?
    let batteryVoltage: Float?
    let workMode: String?
}

// MARK: - TransmissionalData
struct TransmissionalData: Codable {
    let rssi: Int?
    let snr: Double?
    let spreadingFactor: Int?
    let consumedAirtime: Double?
    let bandwidth, frequency: Int?
}
