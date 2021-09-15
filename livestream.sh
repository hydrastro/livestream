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
TEXT_SOURCE="./now_playing.txt"
TEXT_BORDER_H="36"
QUALITY="superfast"
VIDEO_BITRATE="1500k"
AUDIO_BITRATE="128k"
AUDIO_DIR="./music"
RTMP_SERVER="rtmp://${IP}:${PORT}/${STREAMKEY}"
SCRIPT_VERSION="1.2"
LOG_FILE="log"
LOG_LEVEL="lmao"
QUEUE_FILE="./queue.txt"
FIFO_IN="in"
FIFO_OUT="out"

STATUS_STREAMING="STREAMING"
STATUS_OFFLINE="OFFLINE"
STATUS_PAUSED="PAUSED"

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
        -i ./loop.txt                                                          \
        -map 0:v:0 -map 1:a:0                                                  \
        -map_metadata:g 1:g                                                    \
        -vf "drawbox=x=0:y=ih-${TEXT_BORDER_H}:color=${TEXT_BOX_COLOR}:        \
            width=iw:height=${TEXT_BORDER_H}:t=fill,                           \
            drawtext=fontfile=${FONT_FILE}:fontsize=${TEXT_SIZE}:              \
            textfile=${TEXT_SOURCE}:reload=1:fontcolor=${TEXT_COLOR}:          \
            x=(mod(${TEXT_SPEED}*n\,w+tw)-tw):y=h-line_h-10,                   \
            pad=ceil(iw/2)*2:ceil(ih/2)*2"                                     \
        -vcodec libx264                                                        \
        -pix_fmt yuv420p                                                       \
        -preset ${QUALITY}                                                     \
        -r ${FPS}                                                              \
        -g $((FPS * 2))                                                        \
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
        livestream_get_next_audio
        livestream_update_audio_file "$NEXT_AUDIO" $current_file_id
        sleep "$sleep_time"
        sleep_time=$(echo | awk "{print $AUDIO_LENGTH}")
        video_text=$(livestream_get_video_text "$NEXT_AUDIO")
        livestream_update_video_text "$video_text"
        [[ $current_file_id -eq 0 ]] && current_file_id=1 || current_file_id=0
    done
}

function livestream_get_next_audio() {
    if [[ ${#QUEUE[@]} -ne 0 ]]; then
        NEXT_AUDIO=${QUEUE[0]}
        livestream_remove_queue_audio "$NEXT_AUDIO"
    else
        livestream_get_random_audio
        NEXT_AUDIO=$RANDOM_AUDIO
    fi
    if [[ ! -f "$NEXT_AUDIO" ]]; then
        livestream_log "Error: audio file ($NEXT_AUDIO) not found"
        livestream_get_random_audio
        NEXT_AUDIO=$RANDOM_AUDIO
    fi
}

function livestream_remove_queue_audio() {
    if [[ $# -lt 1 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"
        return 1
    fi
    similarity=${2:false}
    if [ "$similarity" = true ]; then
        queue_audio=$(find . -iname "*$1*" -print)
    else
        queue_audio=$1
    fi
    if [[ -z $queue_audio ]]; then
        livestream_log "Requested audio not found."
        FIFO_REPLY="Requested audio not found."
        return 1
    else
        livestream_log "Removing $queue_audio from queue."
    fi
    for i in "${!QUEUE[@]}"; do
        if [[ ${QUEUE[i]} = $queue_audio ]]; then
            unset 'array[i]'
        fi
    done
    QUEUE=("${QUEUE[@]}")
    FIFO_REPLY="Audio successfully removed from queue."
}

function livestream_play() {
    if [[ $# -lt 1 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"
        return 1
    fi
    audio=$(find . -iname "*$1*" -print)
    if [[ -z $audio ]]; then
        livestream_log "Requested audio not found."
        FIFO_REPLY="Requested audio not found."
    else
        QUEUE+=("$audio")
        livestream_log "Audio $audio successfully added to queue."
        FIFO_REPLY="Audio $audio successfully added to queue."
    fi
}

function livestream_show_queue() {
    if [ ${#QUEUE[@]} -eq 0 ]; then
        FIFO_REPLY="Queue is empty."
        return 1
    fi
    FIFO_REPLY="Queue:\n"
    for audio in "${QUEUE[@]}"; do
        FIFO_REPLY+="$audio\n"
    done
}

function livestream_get_random_audio() {
    livestream_load_music
    RANDOM_AUDIO=${MUSIC[$RANDOM % ${#MUSIC[@]}]}
    AUDIO_LENGTH=$(ffprobe -v error -show_entries format=duration -of          \
        default=noprint_wrappers=1:nokey=1 "$RANDOM_AUDIO")
}

function livestream_update_audio_file() {
    if [[ $# -lt 2 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"
        return 1
    fi
    livestream_log "copying $1 into $2"
    if [[ -f "$1" ]]; then
        cp -f "$1" "./audio$2.opus"
    else
        livestream_log "Error: audio file ($1) not found."
    fi
}

function livestream_get_video_text() {
    audio_filename=$(basename "${1%.*}")
    echo "$TEXT_PREFIX$audio_filename"
}

function livestream_update_video_text() {
    if [[ $# -lt 1 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"
        return 1
    fi
    echo "$1" > $TEXT_SOURCE
}

function livestream_load_music() {
    livestream_log "Loading music files."
    i=0
    for entry in "$AUDIO_DIR"/*
    do
        MUSIC[ $i ]="$entry"
        (( i++ ))
    done < <(ls -ls)
}

function livestream_quit() {
    livestream_log "Quitting livestream."
    # shellcheck disable=SC2009
    kill -9 "-$(ps -efj | grep -m 1 'livestream.sh -s' | awk '{print $4}')" && \
    cp -f done.m3u8 stream.m3u8 &&                                             \
    echo "Livestream quit."
    FIFO_REPLY="Livestream stopped."
    exit
}

function livestream_pause() {
    echo "ffconcat version 1.0" > ./loop.txt
    echo "file pause.opus" >> ./loop.txt
    echo "file loop.txt" >> ./loop.txt
    STATUS="$STATUS_PAUSED"
    FIFO_REPLY="Livestream paused."
}

function livestream_create_loop_file() {
    echo "ffconcat version 1.0" > ./loop.txt
    echo "file audio0.opus" >> ./loop.txt
    echo "file audio1.opus" >> ./loop.txt
    echo "file loop.txt" >> ./loop.txt
}

function livestream_resume() {
    livestream_create_loop_file
    STATUS="$STATUS_STREAMING"
    FIFO_REPLY="Livestream resumed."
}

function livestream_log() {
    if [[ $# -lt 1 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"
        return 1
    fi
    if [[ "$LOG_LEVEL" != "NONE" ]]; then
        echo "$(date +'[%Y-%m-%d %H:%M:%S]') $1" >> $LOG_FILE
    fi
}

function livestream_print_status_message() {
    case "$STATUS" in
        "$STATUS_STREAMING"             )
            echo "Livestream is online."
            ;;
         "$STATUS_PAUSED"               )
            echo "Livestream is paused."
            ;;
         "$STATUS_OFFLINE"              )
            echo "Livestream is offline."
            ;;
    esac
}

function livestream_start() {
    if [ "$(pgrep 'livestream.sh' | wc -l)" -gt 2 ]; then
        livestream_log "Livestream is already running."
        exit 1;
    fi
    livestream_log "Starting livestream."
    rm -f audio* "$FIFO_IN" "$FIFO_OUT"
    mkfifo "$FIFO_IN"
    mkfifo "$FIFO_OUT"
    STATUS="$STATUS_STREAMING"
    QUEUE=( )
    livestream_create_loop_file
    livestream_listen
    livestream_manage_audio &
    sleep 1 && livestream_send
    livestream_guard &
    echo "Livestream started."
}

function livestream_guard() {
    while true; do
        if read command < "$FIFO_IN"; then
            livestream_handle_command "$command"
        fi
        sleep 1
    done
}

function livestream_handle_command() {
    if [[ $# -lt 1 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"
        return 1
    fi
    full_command=$1
    command=$(echo "$full_command" | head -n1 | awk '{print $1;}')
    FIFO_REPLY=""
    case "$command" in
        "PAUSE"                               )
            livestream_pause
            ;;
        "RESUME"                              )
            livestream_resume
            ;;
        "PLAY"                                )
            livestream_play ${full_command:5}
            ;;
        "REMOVE"                              )
            livestream_remove ${full_command:7}
            ;;
        "QUEUE"                               )
            livestream_show_queue
            ;;
        "QUIT"                                )
            livestream_quit
            ;;
        "STATUS"                              )
            FIFO_REPLY=$STATUS
            ;;
        *                                     )
            ;;
    esac
    printf "$FIFO_REPLY\n" > "$FIFO_OUT"
}

function livestream_help() {
    livestream_version
    printf "usage: ./livestream [options]\n\n"
    printf "Options:\n"
    printf "  -h | --help          Displays this information.\n"
    printf "  -v | --version       Displays script version.\n"
    printf "  -s | --start         Starts the livestream.\n"
    printf "  -q | --quit          Stops the livestream.\n"
    printf "  -u | --status        Displays this livestream status.\n"
    printf "  -p | --play <arg>    Plays a requested song if it's found.\n"
    printf "  -w | --queue         Displays the queue.\n"
    printf "  -r | --remove <arg>  Removes a requested song from the queue, if it's found.\n"
    printf "  -a | --pause         Pauses the livestream.\n"
    printf "  -e | --resume        Resumes the livestream.\n"
}

function livestream_version() {
    echo "Livestream version $SCRIPT_VERSION"
}

function livestream_send_command() {
    if [[ "$STATUS" == "$STATUS_OFFLINE" ]]; then
        livestream_log "Livestream is not running."
        exit 1;
    fi
    case "$1" in
        "QUIT"                              )
            echo "QUIT" > "$FIFO_IN"
            ;;
        "PLAY"                              )
            echo "PLAY ${@:2}" > "$FIFO_IN"
            ;;
        "QUEUE"                             )
            echo "QUEUE" > "$FIFO_IN"
            ;;
        "REMOVE"                            )
            echo "REMOVE ${@:2}" > "$FIFO_IN"
            ;;
        "PAUSE"                             )
            echo "PAUSE ${@:2}" > "$FIFO_IN"
            ;;
        "STATUS"                            )
            echo "STATUS" > "$FIFO_IN"
            ;;
    esac
    cat "$FIFO_OUT"
    exit 0
}

function livestream_get_status() {
    if [ "$(pgrep 'livestream.sh' | wc -l)" -gt 2 ]; then
        echo "STATUS" > "$FIFO_IN"
        STATUS=$(cat "$FIFO_OUT")
    else
        STATUS="$STATUS_OFFLINE"
    fi
}

function livestream_main() {
    if [[ $# -eq 0 ]]; then
        echo "Please supply at least one argument. Type --help for help."
        exit 1
    fi
    livestream_get_status
    case "$1" in
        "-h" | "--help"                           )
            livestream_help
            ;;
        "-v" | "--version"                        )
            livestream_version
            ;;
        "-s" | "--start"                          )
            livestream_start
            ;;
        "-u" | "--status"                         )
            livestream_print_status_message
            ;;
        "-q" | "--quit"                           )
            livestream_quit
            ;;
        "-p" | "--play"                           )
            livestream_send_command "PLAY" ${@:2}
            ;;
        "-w" | "--queue"                          )
            livestream_send_command "QUEUE"
            ;;
        "-r" | "--remove"                         )
            livestream_send_command "REMOVE" ${@:2}
            ;;
        "-a" | "--pause"                          )
            livestream_send_command "PAUSE"
            ;;
        *                                         )
            echo "Invalid argument(s). Type --help for help."
            exit 1
            ;;
    esac
}

trap livestream_quit SIGTERM SIGINT
livestream_main "$@"
