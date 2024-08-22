# This script gets weather. NOTE! Change the API for your unit or this won't work. Get this from Openweathermap.org
#!/bin/bash

API_KEY="INSERT YOUR API HERE"
UNITS="imperial"
ICON_PATH="/tmp/icons"
IMAGE_PATH="/tmp/noaa_image.png"
CACHE_FILE="/tmp/weather_cache.json"
CACHE_DURATION=86400

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Ensure the icon directory exists
mkdir -p "${ICON_PATH}"

# Fetch location data from ipinfo.io
fetch_ip_location() {
    LOCATION=$(curl -s ipinfo.io)
    LAT=$(echo "$LOCATION" | jq -r '.loc' | cut -d',' -f1)
    LON=$(echo "$LOCATION" | jq -r '.loc' | cut -d',' -f2)
    CITY=$(echo "$LOCATION" | jq -r '.city')
    STATE=$(echo "$LOCATION" | jq -r '.region')
    COUNTRY_CODE=$(echo "$LOCATION" | jq -r '.country')
}

# Fetch GPS location data using Python script
fetch_gps_location() {
    gps_data=$(timeout 30s python3 - <<END
import serial
import time
ser = serial.Serial('/dev/ttyS0', 115200)
ser.flushInput()
rec_buff = ''
ser.write(('AT+CGPS=1,1'+'\r\n').encode())
time.sleep(2)
rec_buff = ser.read(ser.inWaiting())
if 'OK' not in rec_buff.decode():
    print('GPS_DATA_NOT_AVAILABLE')
else:
    ser.write(('AT+CGPSINFO'+'\r\n').encode())
    time.sleep(1)
    rec_buff = ser.read(ser.inWaiting())
    if ',,,,,,' in rec_buff.decode():
        print('GPS_DATA_NOT_AVAILABLE')
    else:
        gps_info = rec_buff.decode().split(',')
        print(f"LAT={gps_info[1]}")
        print(f"LON={gps_info[2]}")
END
    )
    LAT=$(echo "$gps_data" | grep "LAT=" | cut -d'=' -f2)
    LON=$(echo "$gps_data" | grep "LON=" | cut -d'=' -f2)
    CITY="Unknown"
    STATE="Unknown"
    COUNTRY_CODE="Unknown"
}

# Try fetching location data from IP
fetch_ip_location

# If IP location data is not available, fallback to GPS
if [ -z "$LAT" ] || [ -z "$LON" ]; then
    fetch_gps_location
fi

# Check if latitude and longitude were fetched successfully
if [ -z "$LAT" ] || [ -z "$LON" ]; then
  echo -e "Failed to fetch location data.\n\${color orange} \nNo internet connection. For weather data \n please connect RTL-SDR, and monitor \n162.550 MHz (or your local NOAA freq)\n in CubicSDR for current conditions.\${voffset 100}\$color"
  exit 1
fi

# API URLs
CURRENT_WEATHER_URL="http://api.openweathermap.org/data/2.5/weather?lat=${LAT}&lon=${LON}&appid=${API_KEY}&units=${UNITS}"
FORECAST_URL="http://api.openweathermap.org/data/2.5/forecast?lat=${LAT}&lon=${LON}&appid=${API_KEY}&units=${UNITS}"

# Function to fetch weather data from API
fetch_weather_data() {
    current_weather=$(curl -s "${CURRENT_WEATHER_URL}")
    forecast=$(curl -s "${FORECAST_URL}")
    if [ "$(echo "$current_weather" | jq -r '.cod')" == "200" ]; then
        echo "$current_weather" > "$CACHE_FILE"
    else
        return 1
    fi
}

# Fetch current weather data
if ! fetch_weather_data; then
    if [ -f "$CACHE_FILE" ]; then
        echo "Using cached weather data."
        current_weather=$(cat "$CACHE_FILE")
    else
        echo -e "No cached data available.\n\${color orange} \nNo internet connection. For weather data \n please connect RTL-SDR, and monitor \n162.550 MHz (or your local NOAA freq)\n in CubicSDR for current conditions.\${voffset 100}\$color"
        exit 1
    fi
fi

# Extract temperatures and conditions from the current weather
temp_min=$(echo "$current_weather" | jq -r '.main.temp_min' | cut -d. -f1)
temp_max=$(echo "$current_weather" | jq -r '.main.temp_max' | cut -d. -f1)
weather_desc=$(echo "$current_weather" | jq -r '.weather[0].description')
wind_speed=$(echo "$current_weather" | jq -r '.wind.speed' | cut -d. -f1)
wind_deg=$(echo "$current_weather" | jq -r '.wind.deg' | cut -d. -f1)
pressure=$(echo "$current_weather" | jq -r '.main.pressure')

# Extract and format sunrise and sunset
sunrise_time=$(echo "$current_weather" | jq '.sys.sunrise')
sunset_time=$(echo "$current_weather" | jq '.sys.sunset')
sunrise=$(date -d "@$sunrise_time" +'%H:%M')
sunset=$(date -d "@$sunset_time" +'%H:%M')

# Format wind direction and speed
wind_info=$(printf "%03d%02dG%02d" "$wind_deg" "$wind_speed")

# Output current weather
echo "\${color orange}Location:\$color ${CITY}, ${STATE}, ${COUNTRY_CODE}"
echo "\${color orange}Temperature:\$color Low: ${temp_min}°, High: ${temp_max}°"
echo "\${color orange}Current WX:\$color ${weather_desc}"
echo "\${color orange}Wind/Pressure:\$color ${wind_info}     ${pressure} hPa"
echo "\${color orange}Sunrise:\$color $sunrise, \${color orange}Sunset:\$color $sunset"

# Check for weather alerts
alerts=$(echo "$current_weather" | jq '.alerts')
if [ "$alerts" != "null" ] && [ "$alerts" != "[]" ]; then
    echo "\${color red}Weather Alerts:\$color"
    for alert in $(echo "$alerts" | jq -r '.[].event'); do
        echo "\${color red}$alert\$color"
    done
else
    echo "\${color green}No current alerts.\$color"
fi

# Fetch and display lunar data
lunar_data=$(curl -s "http://api.farmsense.net/v1/moonphases/?d=$(date +%s)")
lunar_phase=$(echo "$lunar_data" | jq -r '.[0].Phase')
illumination=$(echo "$lunar_data" | jq -r '.[0].Illumination')
echo "\${color orange}Lunar Phase:\$color $lunar_phase"
echo "\${color orange}Percent Illumination:\$color $illumination%"

# Process and output 3-day forecast
next_days_forecast=$(echo "$forecast" | jq '.list | group_by(.dt_txt[:10]) | .[1:4] | map({
    dt: .[0].dt_txt[:10],
    temp_min: min_by(.main.temp_min) | .main.temp_min,
    temp_max: max_by(.main.temp_max) | .main.temp_max,
    icon: .[0].weather[0].icon,
    description: .[0].weather[0].description
})')

forecast_output="\${color orange}3-Day Forecast:\$color\n"
for day in $(seq 0 2); do
    daily_forecast=$(echo "$next_days_forecast" | jq ".[$day]")
    date=$(echo "$daily_forecast" | jq -r '.dt')
    weekday=$(date -d "$date" +"%a")  # Convert date to weekday abbreviation
    temp_min=$(echo "$daily_forecast" | jq -r '.temp_min' | cut -d. -f1)
    temp_max=$(echo "$daily_forecast" | jq -r '.temp_max' | cut -d. -f1)
    description=$(echo "$daily_forecast" | jq -r '.description')

    # Append each day's forecast to output
    forecast_output+="${weekday} - Low: ${temp_min}°, High: ${temp_max}°, ${description}\n"
done

echo -e "$forecast_output"
