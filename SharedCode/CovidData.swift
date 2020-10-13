//
//  CovidData.swift
//  SharedCode
//
//  Created by Miguel de Icaza on 10/7/20.
//

import Foundation

let formatVersion = 1

/// Imported from the Json file
public struct TrackedLocation: Codable {
    public var title: String!
    public var admin: String!
    public var proviceState: String!
    public var countryRegion: String!
    public var lat, long: String!
}

// Imported from the JSON file, tends to have the last N samples (20 or so)
// the last element is the current status, the delta is the difference
// between the last two elements
public struct Snapshot: Codable {
    public var lastDeaths: [Int]!
    public var lastConfirmed: [Int]!
}

/// All of the locations we are tracking
public struct GlobalData: Codable {
    public var time: Date = Date()
    public var version: Int = formatVersion
    public var globals: [String:TrackedLocation] = [:]
}

public struct IndividualSnapshot: Codable {
    public var time: Date = Date()
    public var version: Int = formatVersion
    public var snapshot: Snapshot
}

public struct SnapshotData: Codable {
    public var time: Date = Date()
    public var version: Int = formatVersion
    public var snapshots: [String:Snapshot] = [:]
}

/// Contains the data for a given location
public struct Stats: Hashable {
    public var updateTime: Date
    
    /// Caption for the location
    public var caption: String
    /// Subcation to show for the location
    public var subCaption: String?
    /// Total number of cases for that location
    public var totalCases: Int
    /// Number of new cases in the last day for that location
    public var deltaCases: Int
    /// Array of total cases since the beginning
    public var cases: [Int]
    /// Array of change of cases per day
    public var casesDelta: [Int]
    /// Total number of deaths in that location
    public var totalDeaths: Int
    /// Total of new deaths in the last day for that location
    public var deltaDeaths: Int
    /// Array of total deaths since the beginning
    public var deaths: [Int]
    /// Array of changes in deaths since the beginning
    public var deathsDelta: [Int]
    public var lat, long: String!
}

func makeDecoder () -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}

public class UpdatableStats: ObservableObject {
    @Published var stat: Stats? = nil
    var code: String
    var tl: TrackedLocation!
    
    public init (code: String)
    {
        self.code = code
        self.tl = globalData.globals [code]
        load ()
    }
    
    func load (){
        let url = URL(string: "https://tirania.org/covid-data/\(code)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) {(data, response, error) in
            guard error == nil else {
                print ("error: \(error!)")
                return
            }
            
            guard let content = data else {
                print("No data")
                return
            }
            let decoder = makeDecoder()
            if let isnap = try? decoder.decode(IndividualSnapshot.self, from: content) {
                DispatchQueue.main.async {
                    self.stat = makeStat(trackedLocation: self.tl, snapshot: isnap.snapshot, date: isnap.time)
                    print ("Data loaded")
                }
            }
        }
        task.resume()
    }
}

extension IndividualSnapshot {
 
    static public func tryLoadCache (name: String) -> IndividualSnapshot?
    {
        if let cacheDir = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let file = cacheDir.appendingPathComponent(name)
            
            if let data = try? Data (contentsOf: file) {
                let decoder = makeDecoder()
                if let snapshot = try? decoder.decode(IndividualSnapshot.self, from: data) {
                    return snapshot
                }
            }
        }
        return nil
    }
}

func load () -> SnapshotData
{
    let idata = try! Data (contentsOf: URL (fileURLWithPath: "/tmp/individual"))
    let d = makeDecoder()
    return try! d.decode(SnapshotData.self, from: idata)
}

public var globalData: GlobalData = {
    let filePath = Bundle.main.url(forResource: "global", withExtension: "")
    if let gd = try? Data(contentsOf: filePath!) {
        let d = makeDecoder()
        return try! d.decode(GlobalData.self, from: gd)
    }
    abort ()
}()
    
var sd: SnapshotData!

var emptyStat = Stats(updateTime: Date(), caption: "Taxachussets", subCaption: nil,
                      totalCases: 1234, deltaCases: +11,
                      cases: [], casesDelta: [],
                      totalDeaths: 897, deltaDeaths: +2,
                      deaths: [], deathsDelta: [])

func makeDelta (_ v: [Int]) -> [Int]
{
    var result: [Int] = []
    var last = v [0]
    
    for i in 1..<v.count {
        result.append (v[i]-last)
        last = v [i]
    }
    return result
}

public func makeStat (trackedLocation: TrackedLocation, snapshot: Snapshot, date: Date = Date()) -> Stats
{
    let last2Deaths = Array (snapshot.lastDeaths.suffix(2))
    let totalDeaths = last2Deaths[1]
    let deltaDeaths = last2Deaths[1]-last2Deaths[0]
    let last2Cases = Array(snapshot.lastConfirmed.suffix(2))
    let totalCases = last2Cases [1]
    let deltaCases = last2Cases[1]-last2Cases[0]
    
    var caption: String
    var subcaption: String?
    
    if trackedLocation.countryRegion == "US" {
        if trackedLocation.admin == nil {
            caption = trackedLocation.proviceState
        } else {
            caption = trackedLocation.admin
            subcaption = trackedLocation.proviceState
        }
    } else {
        if trackedLocation.proviceState == "" {
            caption = trackedLocation.countryRegion
        } else {
            caption = trackedLocation.proviceState
            subcaption = trackedLocation.countryRegion
        }
    }
    return Stats (updateTime: date,
                  caption: caption,
                  subCaption: subcaption,
                  totalCases: totalCases,
                  deltaCases: deltaCases,
                  cases: snapshot.lastConfirmed,
                  casesDelta: makeDelta (snapshot.lastConfirmed),
                  totalDeaths: totalDeaths,
                  deltaDeaths: deltaDeaths,
                  deaths: snapshot.lastDeaths,
                  deathsDelta: makeDelta (snapshot.lastDeaths),
                  lat: trackedLocation.lat,
                  long: trackedLocation.long)
}


public func fetch (code: String) -> Stats
{
    sd = load ()
    
    guard let snapshot = sd.snapshots [code] else {
        emptyStat.caption = "CODE"
        return emptyStat
    }
    guard let tl = globalData.globals [code] else {
        emptyStat.caption = "GLOBAL"
        return emptyStat
    }
        
    return makeStat (trackedLocation: tl, snapshot: snapshot)
}


var fmtDecimal: NumberFormatter = {
    var fmt = NumberFormatter()
    fmt.numberStyle = .decimal
    fmt.maximumFractionDigits = 2
    
    return fmt
} ()

var fmtDecimal1: NumberFormatter = {
    var fmt = NumberFormatter()
    fmt.numberStyle = .decimal
    fmt.maximumFractionDigits = 1
    
    return fmt
} ()

var fmtNoDecimal: NumberFormatter = {
    var fmt = NumberFormatter()
    fmt.numberStyle = .decimal
    fmt.maximumFractionDigits = 0
    return fmt
} ()


public func fmtLarge (_ n: Int) -> String
{
    switch n {
    case let x where x < 0:
        return "0."     // "0." as a flag to determine something went wrong
        
    case 0..<99999:
        return fmtDecimal.string(from: NSNumber (value: n)) ?? "?"
        
    case 100000..<999999:
        return (fmtNoDecimal.string(from: NSNumber (value: Float (n)/1000.0)) ?? "?") + "k"
        
    default:
        return fmtNoDecimal.string(from: NSNumber (value: Float (n)/1000000.0)) ?? "?" + "M"
    }
}

public func fmtDigit (_ n: Int) -> String {
    return fmtDecimal.string (from: NSNumber (value: n)) ?? "?"
}

public func fmtDelta (_ n: Int) -> String
{
    switch n {
    case let x where x < 0:
        return "-0"     // "-0" as a flag to determine something went wrong
        
    case 0..<9999:
        return "+" + (fmtDecimal.string(from: NSNumber (value: n)) ?? "?")
        
    case 10000..<999999:
        return "+" + (fmtDecimal1.string(from: NSNumber (value: Float (n)/1000.0)) ?? "?") + "k"
        
    default:
        return "+" + (fmtDecimal.string(from: NSNumber (value: Float (n)/1000000.0)) ?? "?") + "M"
    }
}

