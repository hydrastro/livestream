#!/bin/bash

IP="127.0.0.1"
PORT="6645"
STREAMKEY="stream"
VIDEO_SOURCE="video.mp4"
AUDIO_DIR="music"
FONT_FILE="./fonts/FSEX302.ttf"
TEXT_PREFIX="Now playing: "
TEXT_SPEED="2"
TEXT_SIZE="25"
TEXT_BOX_COLOR="black@0.5"
TEXT_X="30"
TEXT_Y="30"
TEXT_SOURCE="./text.txt"
TEXT_BORDER_W="40"
TEXT_BOX="1"
QUALITY="superfast"
FPS="30"
VBR="1500k"
RTMP_SERVER="rtmp://${IP}:${PORT}/${STREAMKEY}"

livestream_send() {
    ffmpeg                                                                    \
        -re                                                                   \
        -stream_loop -1                                                       \
        -f lavfi                                                              \
        -i "movie=filename=${VIDEO_SOURCE}:loop=0, setpts=N/(FRAME_RATE*TB)"  \
        -thread_queue_size 512                                                \
        -i list.txt                                                           \
        -map 0:v:0 -map 1:a:0                                                 \
        -map_metadata:g 1:g                                                   \
        -vf "drawbox=x=0:y=ih-${TEXT_BORDER_W}:color=${TEXT_BOX_COLOR}:       \
            width=iw:height=${TEXT_BORDER_W}:t=fill,                          \
            drawtext=fontfile=${FONT_FILE}: fontsize=${TEXT_SIZE}:            \
            textfile=${TEXT_SOURCE}: reload=1: fontcolor=white@0.8:           \
            x=(mod(2*n\,w+tw)-tw):y=h-line_h-10"                              \
        -vcodec libx264                                                       \
        -pix_fmt yuv420p                                                      \
        -preset ${QUALITY}                                                    \
        -r ${FPS}                                                             \
        -g $((${FPS} * 2))                                                    \
        -b:v ${VBR}                                                           \
        -acodec libmp3lame                                                    \
        -ar 44100                                                             \
        -threads 6                                                            \
        -qscale:v 3                                                           \
        -b:a 320000                                                           \
        -bufsize ${VBR}                                                       \
        -f flv "${RTMP_SERVER}"
}
#        -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \

livestream_listen() {
    ffmpeg                                                                    \
        -listen 1                                                             \
        -timeout -1                                                           \
        -i "$RTMP_SERVER"                                                     \
        -c:v copy                                                             \
        -c:a copy                                                             \
        -flags +cgop                                                          \
        -g "$FPS"                                                             \
        -hls_time 2                                                           \
        -hls_list_size 5                                                      \
        -hls_allow_cache 1                                                    \
        -hls_flags delete_segments                                            \
       -flush_packets 1 stream.m3u8;                                          \
    cp -f done.m3u8 stream.m3u8;
}

livestream_send_loop() {
    # TODO: get pid
    livestream_send &
    while true; do
        livestream_get_random_audio
        livestream_update_video_text $random_audio
        livestream_update_queue_file $random_audio
        sleep_time=$(echo|awk "{print $audio_length - 1}")
        sleep $sleep_time
    done
}

livestream_get_random_audio() {
    random_audio=${MUSIC[$RANDOM % ${#MUSIC[@]} ]}
    audio_length=$(ffprobe -v error -show_entries format=duration -of \
        default=noprint_wrappers=1:nokey=1 $random_audio)
}

livestream_update_queue_file() {
    printf "ffconcat version 1.0\nfile '$1'\nfile list.txt" > list.txt
}

livestream_update_video_text() {
    audio_filename=$(basename "${1%.*}")
    echo $TEXT_PREFIX$audio_filename > ${TEXT_SOURCE}
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
        echo $pid
        kill -0 "$pid" && kill "$pid"
    done
}
}
PIDS=( )
trap livestream_quit EXIT

livestream_load_music

livestream_listen & \
sleep 2 && \
livestream_send_loop
