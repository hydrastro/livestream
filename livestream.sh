#!/bin/bash

IP="127.0.0.1"
PORT="6645"
STREAMKEY="stream"
FPS="30"
VIDEO_SOURCE="./video.mp4"
FONT_FILE="./fonts/FSEX302.ttf"
TEXT_PREFIX="Now playing: "
TEXT_SPEED="1"
TEXT_SIZE="20"
TEXT_BOX_COLOR="black@0.5"
TEXT_SOURCE="./text.txt"
TEXT_BORDER_H="40"
QUALITY="superfast"
VIDEO_BITRATE="1500k"
AUDIO_BITRATE="128k"
AUDIO_DIR="./music"
RTMP_SERVER="rtmp://${IP}:${PORT}/${STREAMKEY}"

livestream_send() {
    ffmpeg                                                                     \
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
            textfile=${TEXT_SOURCE}:reload=1:fontcolor=white@0.8:              \
            x=(mod(2*n\,w+tw)-tw):y=h-line_h-10"                               \
        -vcodec libx264                                                        \
        -pix_fmt yuv420p                                                       \
        -preset ${QUALITY}                                                     \
        -r ${FPS}                                                              \
        -g $((${FPS} * 2))                                                     \
        -b:v ${VIDEO_BITRATE}                                                  \
        -acodec libmp3lame                                                     \
        -ar 44100                                                              \
        -threads 6                                                             \
        -qscale:v 3                                                            \
        -b:a ${AUDIO_BITRATE}                                                  \
        -flush_packets 0 \
        -bufsize 512k                                                          \
        -f flv "${RTMP_SERVER}"
}
#        -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \

livestream_listen() {
    ffmpeg                                                                     \
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
        -flush_packets 1 stream.m3u8;                                          \
    cp -f done.m3u8 stream.m3u8;
}

livestream_manage_audio() {
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

livestream_send_loop() {
    livestream_manage_audio &
    livestream_send
}

livestream_get_random_audio() {
    RANDOM_AUDIO=${MUSIC[$RANDOM % ${#MUSIC[@]} ]}
    AUDIO_LENGTH=$(ffprobe -v error -show_entries format=duration -of \
        default=noprint_wrappers=1:nokey=1 "$RANDOM_AUDIO")
}

livestream_update_audio_file() {
    cp -f "$1" ./audio$2.opus
}

livestream_get_video_text() {
    audio_filename=$(basename "${1%.*}")
    echo "$TEXT_PREFIX$audio_filename"
}

livestream_update_video_text() {
    echo "$1" > ${TEXT_SOURCE}
}

livestream_load_music() {
    i=0
    for entry in ${AUDIO_DIR}/*
    do
        MUSIC[ $i ]="$entry"
        (( i++ ))
    done < <(ls -ls)
}

livestream_quit() {
    for pid in "${PIDS[@]}"; do
        read -p "killing someone"
        kill -0 "$pid" && kill "$pid"
    done
}

livestream_log() {
    echo -n "date +"[%m-%d %H:%M:%S]" & $1" > livestream.log
}

while true; do
    livestream_load_music
    livestream_listen &
    livestream_send_loop
done
