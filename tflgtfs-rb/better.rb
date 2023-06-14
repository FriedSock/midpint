TFL_API_KEY = ENV["TFL_API_KEY"]
GTFS_PATH = "./gtfs"
CACHE_PATH = "./cache"

require 'active_support'
require 'concurrent-edge'
require 'faraday'
require 'faraday/http_cache'
require 'faraday/retry'
require 'csv'
require 'digest'

SERVICES =
  [
      "School Monday",
      "Sunday Night/Monday Morning",
      "School Monday",
      "Tuesday",
      "Monday - Thursday",
      "Saturday",
      "Saturday and Sunday",
      "Sunday",
      "School Tuesday",
      "Saturday Night/Sunday Morning",
      "Mo-Fr Night/Tu-Sat Morning",
      "Monday to Thursday",
      "Mo-Th Nights/Tu-Fr Morning",
      "Saturday (also Good Friday)",
      "Mon-Th Schooldays",
      "Saturdays and Public Holidays",
      "Friday Night/Saturday Morning",
      "Friday",
      "Thursdays",
      "Sunday night/Monday morning - Thursday night/Friday morning",
      "School Thursday",
      "School Friday",
      "Daily",
      "Tuesday",
      "Mon-Fri Schooldays",
      "Wednesday",
      "Monday",
      "Wednesdays",
      "Monday to Friday",
      "Monday",
      "Sunday and other Public Holidays",
      "School Wednesday",
      "Monday - Friday",
]

Line = Struct.new(
  'Line',
  :id,
  :name,
  :mode_name,
  :route_sections
)

Sequence = Struct.new(
  'Sequence',
  :line_strings,
)

Stop = Struct.new(
  'Stop',
  :id,
  :name,
  :lat,
  :lon,
)

RouteSection = Struct.new(
  'RouteSection',
  :name,
  :direction,
  :originator,
  :destination,
  :timetables,
)

Timetable = Struct.new(
  'Timetable',
  :station_intervals,
  :schedules,
  :stops,
)

StationInterval = Struct.new(
  'StationInterval',
  :stop_id,
  :time_to_arrival
)

Schedule = Struct.new(
  'Schedule',
  :name,
  :known_journeys
)

KnownJourney = Struct.new(
  'KnownJourney',
  :hour,
  :minute,
  :interval_id,
)

Trip = Struct.new(
  'Trip',
  :service_id,
  :id,
  :route_id,
)


def retry_options
  {
    max: 2,
    interval: 0.05,
    interval_randomness: 0.5,
    backoff_factor: 2
  }
end

def conn
  @conn ||= Faraday.new(
    url: 'https://api.tfl.gov.uk',
    params: { app_key: TFL_API_KEY },
  ) do |f|
    f.use :http_cache, store: store
    f.request :retry, retry_options
    f.request :json # encode req bodies as JSON and automatically set the Content-Type header
    f.response :json
  end
end

ROUTE_TYPE = {
  dlr: "0",
  tram: "0",
  tube: "1",
  overground: "1",
  :"elizabeth-line" => "1",
  :"national-rail" => "2",
  bus: "3",
  :"river-tour" => "4",
  :"cable-car" => "5"
}.tap do |h|
  h.default = "2"
end

def store
  @store ||= ActiveSupport::Cache::FileStore.new('./cache')
end

BULLSHIT_LINES = [
  'west-midlands-trains',
  'scotrail',
  'northern-rail',
  'cross-country',
  'east-midlands-railway',
  'first-transpennine-express',
  'transport-for-wales',
  'west-midlands-trains',
  'great-northern'
]

def get_lines
  throttle = Concurrent::Throttle.new 3

  conn.get("/line/route").body.map do |l|
    if l['modeName'] != 'tube'
      next
    end

    #Concurrent::Promises.future_on(throttle.on(Concurrent::Promises.default_executor)) do
      get_line(l)
    #end
  end.compact
end

def get_line(l)
  route_sections = l["routeSections"].map do |r|
    timetables = get_timetable(l["id"], r["originator"], r["destination"])
    puts "#{l["id"]}, #{r["name"]}, #{l["modeName"]}"
    next if timetables.count == 0

    RouteSection.new(
      name: r["name"],
      direction: r["direction"],
      originator: r["originator"],
      destination: r["destination"],
      timetables: timetables,
    )
  end
  Line.new(
    id: l["id"],
    name: l["name"],
    mode_name: l["modeName"],
    route_sections: route_sections.compact,
  )
end

def get_timetable(line_id, originator, destination)
  timetable_response = conn.get("/line/#{line_id}/timetable/#{originator}/to/#{destination}").body

  # This means there has been a error. Typically a 500 error
  return [] if timetable_response.has_key?("httpStatusCode") || timetable_response["stops"].nil? || timetable_response["stops"].empty?

  stops = {}.tap do |h|
    timetable_response["stops"].each do |s|
      h[s["id"]] ||= Stop.new(
        id: s["id"],
        name: s["name"],
        lat: s["lat"],
        lon: s["lon"],
      )
    end
  end

  timetable_response["timetable"]["routes"].map do |t|
    station_intervals = {}.tap do |station_intervals|
      t["stationIntervals"].each do |station_interval_set|
        station_intervals[station_interval_set["id"]] = station_interval_set["intervals"].map do |i|
          StationInterval.new(stop_id: i["stopId"], time_to_arrival: i["timeToArrival"])
        end
      end
    end

    schedules = t["schedules"].map do |s|
      known_journeys = s["knownJourneys"].map do |kj|
        KnownJourney.new(
          hour: kj["hour"].to_i,
          minute: kj["minute"].to_i,
          interval_id: kj["intervalId"],
        )
      end
      Schedule.new(
        name: s["name"],
        known_journeys: known_journeys,
      )
    end

    Timetable.new(
      station_intervals: station_intervals,
      schedules: schedules,
      stops: stops.values,
    )
  end
end


def run
  lines = get_lines.compact
  write_gtfs(lines)
end

def write_gtfs(lines)
  write_agency
  write_routes(lines)
  write_stops(lines)
  write_stop_times(lines)
  write_calendar
  write_trips
end

def write_agency
  CSV.open(File.join(GTFS_PATH, "agency.txt") , "w+") do |csv|
    csv << ["agency_id","agency_name","agency_url","agency_timezone"]
    csv << ["tfl","Transport For London","https://tfl.gov.uk","Europe/London"]
  end
end

def write_routes(lines)
  CSV.open(File.join(GTFS_PATH, "routes.txt") , "w+") do |csv|
    csv << ["route_id", "agency_id", "route_short_name", "route_type"]
    lines.each do |l|
      csv << [l.id, "tfl", l.name, ROUTE_TYPE[l.mode_name.to_sym]]
    end
  end
end

def written_stop_ids
  @written_stop_ids ||= Set.new
end

def write_stops(lines)
  CSV.open(File.join(GTFS_PATH, "stops.txt") , "w+") do |csv|
    csv << ["stop_id", "stop_name", "stop_lat", "stop_lon"]
    lines.each do |l|
      l.route_sections.each do |rs|
        rs.timetables.each do |timetable|
          next if timetable.stops.nil?

          timetable.stops.each do |s|
            if !written_stop_ids.include? s.id
              csv << [s.id, s.name, s.lat, s.lon]
              written_stop_ids.add s.id
            end
          end
        end
      end
    end
  end
end

def write_calendar
  CSV.open(File.join(GTFS_PATH, "calendar.txt") , "w+") do |csv|
    start_date = "20230413"
    end_date = "20240413"

    write_line = ->(partial_line) do
      csv << partial_line + [start_date, end_date]
    end
    csv << ["service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "start_date", "end_date"]
    [
      ["School Monday", "1", "0", "0", "0", "0", "0", "0"],
      ["Sunday Night/Monday Morning", "1", "0", "0", "0", "0", "0", "1"],
      ["School Monday, Tuesday, Thursday & Friday", "1", "1", "0", "1", "1", "0", "0"],
      ["Tuesday", "0", "1", "0", "0", "0", "0", "0"],
      ["Monday - Thursday", "1", "1", "1", "1", "0", "0", "0"],
      ["Saturday", "0", "0", "0", "0", "0", "1", "0"],
      ["Saturday and Sunday", "0", "0", "0", "0", "0", "1","1"],
      ["Sunday", "0", "0", "0", "0", "0", "0", "1"],
      ["School Tuesday", "0", "1", "0", "0", "0", "0", "0"],
      ["Saturday Night/Sunday Morning", "0", "0", "0", "0", "0", "1", "1"],
      ["Mo-Fr Night/Tu-Sat Morning", "1", "1", "1", "1","1", "1", "0"],
      ["Monday to Thursday", "1", "1", "1", "1", "0", "0", "0"],
      ["Mo-Th Nights/Tu-Fr Morning", "1", "1", "1", "1", "1", "0", "0"],
      ["Saturday (also Good Friday)", "0", "0", "0", "0", "0", "1", "0"],
      ["Mon-Th Schooldays", "1", "1", "1", "1", "0", "0", "0"],
      ["Saturdays and Public Holidays", "0", "0", "0", "0", "0", "1", "0"],
      ["Friday Night/Saturday Morning", "0", "0", "0", "0", "1", "1", "0"],
      ["Friday", "0", "0", "0", "0", "1", "0", "0"],
      ["Thursdays", "0", "0", "0", "1", "0", "0", "0"],
      ["Sunday night/Monday morning - Thursday night/Friday morning", "1", "1", "1", "1", "1", "0", "1"],
      ["School Thursday", "0", "0", "0", "1", "0", "0", "0"],
      ["School Friday", "0", "0", "0", "0", "1", "0", "0"],
      ["Daily", "1", "1", "1", "1", "1", "1", "1"],
      ["Tuesday, Wednesday & Thursday", "0", "1", "1", "1", "0", "0", "0"],
      ["Mon-Fri Schooldays", "1", "1", "1", "1", "1", "0", "0"],
      ["Wednesday", "0", "0", "1", "0", "0", "0", "0"],
      ["Monday, Tuesday and Thursday", "1", "1", "0", "1", "0", "0", "0"],
      ["Wednesdays", "0", "0", "1", "0", "0", "0", "0"],
      ["Monday to Friday", "1", "1", "1", "1", "1", "0", "0"],
      ["Monday", "1", "0", "0", "0", "0", "0", "0"],
      ["Sunday and other Public Holidays", "0", "0", "0", "0", "0", "0", "1"],
      ["School Wednesday", "0", "0", "1", "0", "0", "0", "0"],
      ["Monday - Friday", "1", "1", "1", "1", "1", "0", "0"],
    ].each do |l|
      write_line[l]
    end
  end
end

def write_trips
  CSV.open(File.join(GTFS_PATH, "trips.txt") , "w+") do |csv|
    csv << ["route_id", "service_id", "trip_id"]
    trips.each do |key, trip|
      csv << [trip.route_id, trip.service_id, trip.id]
    end
  end
end

def write_stop_times(lines)
  CSV.open(File.join(GTFS_PATH, "stop_times.txt") , "w+") do |csv|
    csv << ["trip_id", "stop_id", "stop_sequence", "arrival_time", "departure_time"]
    lines.each do |line|
      line.route_sections.each do |route_section|
        route_section.timetables.each do |timetable|
          timetable.schedules.each do |schedule|
            schedule.known_journeys.each do |kj|
              trip_id = get_trip_id(line.id, route_section, schedule, kj)
              stop_seq = 1
              trip_start_time = format_time(kj)
              csv << [trip_id, route_section.originator, stop_seq, trip_start_time, trip_start_time]
              intervals = timetable.station_intervals[kj.interval_id.to_s]
              intervals.each do |si|
                stop_seq += 1
                arrival_time = format_time(kj, offset: si.time_to_arrival)
                csv << [trip_id, si.stop_id, stop_seq, arrival_time, arrival_time]
              end
            end
          end
        end
      end
    end
  end
end

# We need a special function because for times representing "after midnight on the day that the timetable schedule started", 24/25/26 etc are used as the
# starting hour for the time, which isn't a real timej
def format_time(known_journey, offset: 0.0)
  hour = known_journey.hour
  min = known_journey.minute
  new_min = (min + offset) % 60
  new_hour = (hour + ((offset + min) / 60)).to_i

  "#{new_hour.to_s.rjust(2, '0')}:#{new_min.to_i.to_s.rjust(2, '0')}:00"
end

def trips
  @trips ||= {}
end

def get_trip(id)
  trips[id]
end

def persist_trip!(id, trip)
  trips[id] = trip
end

def cunt_services
  @cunt_services ||= Set.new
end

def get_trip_id(line_id, route_section, schedule, known_journey)
  key = line_id + route_section.originator + route_section.destination + schedule.name + known_journey.hour.to_s + known_journey.minute.to_s
  md5 = Digest::MD5.new
  md5.update(key).hexdigest.tap do |trip_id|
    if get_trip(trip_id).nil?
      trip = Trip.new(id: trip_id, route_id: line_id, service_id: schedule.name)
      cunt_services.add(schedule.name) if !SERVICES.include?(schedule.name)
      persist_trip!(trip_id, trip)
    end
  end
end

run

puts cunt_services.to_a
