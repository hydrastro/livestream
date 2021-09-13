#!/bin/bash

IP="127.0.0.1"
PORT="6645"
STREAMKEY="stream"
FPS="30"
VIDEO_SOURCE="./video.mp4"
FONT_FILE="./fonts/FSEX302.ttf"
TEXT_PREFIX="Now playing: "
TEXT_SPEED="1"
TEXT_SIZE="18"
TEXT_BOX_COLOR="black@0.5"
TEXT_COLOR="white@0.8"
TEXT_SOURCE="./text.txt"
TEXT_BORDER_H="36"
QUALITY="superfast"
VIDEO_BITRATE="1500k"
AUDIO_BITRATE="128k"

AUDIO_DIR="./music"
RTMP_SERVER="rtmp://${IP}:${PORT}/${STREAMKEY}"
LIVESTREAM_VERSION="1.1"
LIVESTREAM_LOG_FILE="log"
LIVESTREAM_LOG_LEVEL="NONE"

function livestream_send() {
    livestream_log "Starting streaming."
    ffmpeg                                                                     \
        -hide_banner                                                           \
        -loglevel error                                                        \
        -re                                                                    \
        -stream_loop -1                                                        \
        -f lavfi                                                               \
        -i "movie=filename=${VIDEO_SOURCE}:loop=0, setpts=N/(FRAME_RATE*TB)"   \
        -thread_queue_size 512                                                 \
        -i ./list.txt                                                          \
        -map 0:v:0 -map 1:a:0                                                  \
        -map_metadata:g 1:g                                                    \
        -vf "drawbox=x=0:y=ih-${TEXT_BORDER_H}:color=${TEXT_BOX_COLOR}:        \
            width=iw:height=${TEXT_BORDER_H}:t=fill,                           \
            drawtext=fontfile=${FONT_FILE}:fontsize=${TEXT_SIZE}:              \
            textfile=${TEXT_SOURCE}:reload=1:fontcolor=${TEXT_COLOR}:          \
            x=(mod(2*n\,w+tw)-tw):y=h-line_h-10,                               \
            pad=ceil(iw/2)*2:ceil(ih/2)*2"                                     \
        -vcodec libx264                                                        \
        -pix_fmt yuv420p                                                       \
        -preset ${QUALITY}                                                     \
        -r ${FPS}                                                              \
        -g $((${FPS} * 2))                                                     \
        -b:v ${VIDEO_BITRATE}                                                  \
        -acodec libmp3lame                                                     \
        -ar 44100                                                              \
        -threads 6                                                             \
        -b:a ${AUDIO_BITRATE}                                                  \
        -flush_packets 0                                                       \
        -bufsize 512k                                                          \
        -f flv "${RTMP_SERVER}" &
}

function livestream_listen() {
    livestream_log "Starting listening server."
    ffmpeg                                                                     \
        -hide_banner                                                           \
        -loglevel error                                                        \
        -listen 1                                                              \
        -timeout -1                                                            \
        -i "$RTMP_SERVER"                                                      \
        -c:v copy                                                              \
        -c:a copy                                                              \
        -flags +cgop                                                           \
        -g "$FPS"                                                              \
        -hls_time 2                                                            \
        -hls_list_size 5                                                       \
        -hls_allow_cache 1                                                     \
        -hls_flags delete_segments                                             \
        -flush_packets 1 stream.m3u8 &
}

function livestream_manage_audio() {
    livestream_get_random_audio
    video_text=$(livestream_get_video_text "$RANDOM_AUDIO")
    livestream_update_video_text "$video_text"
    livestream_update_audio_file "$RANDOM_AUDIO" 0
    sleep_time=$(echo | awk "{printf $AUDIO_LENGTH}")
    current_file_id=1
    while true; do
        livestream_get_random_audio
        livestream_update_audio_file "$RANDOM_AUDIO" $current_file_id
        sleep $sleep_time
        sleep_time=$(echo | awk "{print $AUDIO_LENGTH}")
        video_text=$(livestream_get_video_text "$RANDOM_AUDIO")
        livestream_update_video_text "$video_text"
        [[ $current_file_id == 0 ]] && current_file_id=1 || current_file_id=0
    done
}

function livestream_get_random_audio() {
    livestream_load_music
    RANDOM_AUDIO=${MUSIC[$RANDOM % ${#MUSIC[@]} ]}
    AUDIO_LENGTH=$(ffprobe -v error -show_entries format=duration -of \
        default=noprint_wrappers=1:nokey=1 "$RANDOM_AUDIO")
}

function livestream_update_audio_file() {
    cp -f "$1" ./audio$2.opus
}

function livestream_get_video_text() {
    audio_filename=$(basename "${1%.*}")
    echo "$TEXT_PREFIX$audio_filename"
}

function livestream_update_video_text() {
    echo "$1" > ${TEXT_SOURCE}
}

function livestream_load_music() {
    livestream_log "Loading music files."
    i=0
    for entry in ${AUDIO_DIR}/*
    do
        MUSIC[ $i ]="$entry"
        (( i++ ))
    done < <(ls -ls)
}

function livestream_quit() {
    livestream_log "Quitting livestream."
    kill -9 -$(ps -efj | grep -m 1 "livestream.sh -s" | awk '{print $4}') &&   \
    cp -f done.m3u8 stream.m3u8 &&                                             \
    echo "Livestream stopped."
    exit
}

function livestream_log() {
    if $LIVESTREAM_LOG_LEVEL != "NONE"; then
        echo "$(date +'[%Y-%m-%d %H:%M:%S]') $1" >> $LIVESTREAM_LOG_FILE
    fi
}

function livestream_status() {
    if [ $(pgrep "livestream.sh" | wc -l) -gt "2" ]; then
        echo "Livestream is online."
    else
        echo "Livestream is offline."
    fi
    exit 0;
}

function livestream_start() {
    if [ $(pgrep "livestream.sh" | wc -l) -gt "2" ]; then
        livestream_log "Livestream is already running."
        exit 1;
    fi
    livestream_log "Starting livestream."
    rm -f audio*
    livestream_listen
    livestream_manage_audio &
    sleep 1 && livestream_send
    livestream_guard&
    echo "Livestream started."
}

function livestream_guard() {
    while true; do
        sleep 1
    done
}

function livestream_help() {
    echo "lol"
}

function livestream_version() {
    echo "Livestream version $LIVESTREAM_VERSION"
}

function livestream_main() {
    if [[ $# -eq 0 ]]; then
         echo "Please supply at least one argument. Type --help for help."
        exit 1
    fi
    case "$1" in
        "-h" | "--help"      )
            livestream_help
            ;;
        "-v" | "--version"   )
            livestream_version
            ;;
        "-s" | "--start"     )
            livestream_start
            ;;
        "-u" | "--status"    )
            livestream_status
            ;;
        "-q" | "--quit"      )
            livestream_quit
            ;;
        *)
            echo "Invalid argument(s). Type --help for help."
            exit 1
            ;;
    esac
}

trap livestream_quit SIGTERM SIGINT
livestream_main $@
