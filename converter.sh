#!/bin/bash
set -e
export LC_NUMERIC="en_US.UTF-8"

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages with color
log() {
    local level="$1"
    local message="$2"

    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
        *)
            echo -e "${NC}[LOG]${NC} $message"
            ;;
    esac
}

validate_dependency() {
    local dependency="$1"
    # Check if dependency is installed
    if ! command -v $dependency &> /dev/null; then
        log "ERROR" "$dependency is not installed. Please install $dependency and try again."
        exit 1
    fi
}

validate_dependencies() {
    # Check if ffmpeg is installed
    validate_dependency "ffmpeg"

    # Check if ffprobe is installed
    validate_dependency "ffprobe"

    # Check if exiftool is installed
    validate_dependency "exiftool"
}

validate_codec() {
    local codec="$1"
    local file="$2"
    log "DEBUG" "Validating codec $codec for $file"
    file_codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file")
    if [ "$codec" = "$file_codec" ]; then
        log "INFO" "Codec $codec validation passed for $file."
    else
        log "ERROR" "Codec validation failed: $file have codec $file_codec, should have codec $codec."
        exit 1
    fi
}

validate_video_length() {
    local file="$1"
    local new_file="$2"
    log "DEBUG" "Validating video length for $file and $new_file"
    # Get the duration of the MP4 file
    mp4_duration=$(ffprobe -v error -select_streams v:0 -show_entries format=duration -of csv=p=0 "$file")
    # Get the duration of the MKV file
    mkv_duration=$(ffprobe -v error -select_streams v:0 -show_entries format=duration -of csv=p=0 "$new_file")
    log "DEBUG" "MP4 Duration: $mp4_duration"
    log "DEBUG" "MKV Duration: $mkv_duration"
    if [ "$(printf "%.0f" "$mp4_duration")" -eq "$(printf "%.0f" "$mkv_duration")" ]; then
        log "INFO" "Validation passed: $file and $new_file have the same duration. mp4:$mp4_duration - mkv:$mkv_duration"
    else
        log "ERROR" "Validation failed: $file and $new_file have different durations. mp4:$mp4_duration - mkv:$mkv_duration"
        exit 1
    fi
}

validate_video_quality() {
    local file="$1"
    local new_file="$2"
    log "DEBUG" "Validating video quality for $file and $new_file"
    ffmpeg_output=$(ffmpeg -i "$file" -i "$new_file" -lavfi "[0:v][1:v]ssim;[0:v][1:v]psnr" -f null - 2>&1)
    ssim=$(echo "$ffmpeg_output" | grep "SSIM" | awk -F 'All:' '{print $2}' | awk '{print $1}')
    psnr=$(echo "$ffmpeg_output" | grep "PSNR" | awk -F 'average:' '{print $2}' | awk '{print $1}')

    # Display the results
    log "DEBUG" "SSIM: $ssim"
    log "DEBUG" "PSNR: $psnr"

    # Check if the SSIM value is acceptable (example threshold)
    if awk "BEGIN {exit !($ssim > 0.95)}"; then
        log "INFO" "Quality check passed for $new_file with SSIM: $ssim and PSNR: $psnr"
    else
        log "ERROR" "Quality check failed for $new_file with SSIM: $ssim and PSNR: $psnr"
        exit 1
    fi
}

validate_video() {
    local file="$1"
    local new_file="$2"

    if [ -f "$new_file" ]; then
        log "DEBUG" "Matching MKV file found: $new_file"
        validate_codec "hevc" "$new_file"
        validate_video_length "$file" "$new_file"
        validate_video_quality "$file" "$new_file"
    else
        log "ERROR" "No matching file found for: $new_file"
        exit 1
    fi
}

convert_video() {
    local file="$1"
    local new_file="${file%.*}.mkv"

    if [ -f "$new_file" ]; then
        log "WARNING" "Skipping conversion as $new_file already exists."
        validate_video "$file" "$new_file"
        return
    fi

    log "INFO" "Converting $file to $new_file..."
    ffmpeg -i "$file" -c:v libx265 -vtag hvc1 -c:a copy "$new_file"
    exiftool -overwrite_original_in_place -TagsFromFile "$file" "-FileModifyDate>FileModifyDate" "$new_file"

    validate_video "$file" "$new_file"
    log "INFO" "Converted $file to $new_file successfully!"
}

perform_video_conversions() {
    # find and process each .mp4 file
    find . -name "*.mp4" | while IFS= read -r file; do
        log "INFO" "Processing file: $file"
        validate_codec "h264" "$file"
        convert_video "$file"
    done
}

# Main function
main() {
    log "INFO" "Starting video conversion"

    validate_dependencies

    perform_video_conversions

    log "INFO" "Video conversion completed"
}

# Entry point
main "$@"
