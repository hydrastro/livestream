#!/bin/bash

# Server settings
: "${IP:=127.0.0.1}"
: "${PORT:=6645}"
: "${STREAMKEY:=stream}"

# Video settings
: "${FPS:=30}"
: "${QUALITY:=superfast}"
: "${VIDEO_BITRATE:=1500k}"
: "${VIDEO_SOURCE:=./video.mp4}"

# Video text settings
: "${FONT_FILE:=./fonts/FSEX302.ttf}"
: "${TEXT_SOURCE:=./now_playing.txt}"
: "${TEXT_PREFIX:=Now playing: }"
: "${TEXT_SPEED:=1}"
: "${TEXT_SIZE:=18}"
: "${TEXT_BOX_COLOR:=black@0.5}"
: "${TEXT_COLOR:=white@0.8}"
: "${TEXT_BORDER_H:=36}"

# Audio settings
: "${AUDIO_BITRATE:=128k}"
: "${AUDIO_DIR:=./music}"

# Logging settings
: "${LOG_FILE:=log}"
: "${LOG_LEVEL:=WARN}"

# Advanced settings
: "${FIFO_IN:=in}"
: "${FIFO_OUT:=out}"

RTMP_SERVER="rtmp://${IP}:${PORT}/${STREAMKEY}"
SCRIPT_VERSION="1.3"
LOG_LEVEL_DEBUG="DEBUG"
LOG_LEVEL_INFO="INFO"
LOG_LEVEL_WARN="WARN"
LOG_LEVEL_ERROR="ERROR"
declare -A LOG_LEVELS
LOG_LEVELS["$LOG_LEVEL_DEBUG"]=0
LOG_LEVELS["$LOG_LEVEL_INFO"]=1
LOG_LEVELS["$LOG_LEVEL_WARN"]=2
LOG_LEVELS["$LOG_LEVEL_ERROR"]=3
STATUS_STREAMING="STREAMING"
STATUS_OFFLINE="OFFLINE"
STATUS_PAUSED="PAUSED"

function livestream_send() {
    local ffmpeg_options
    livestream_log "Starting streaming."
    ffmpeg_options=(
        -hide_banner
        -loglevel error
        -re
        -stream_loop -1
        -f lavfi
        -i "movie=filename=${VIDEO_SOURCE}:loop=0, setpts=N/(FRAME_RATE*TB)"
        -thread_queue_size 512
        -i ./loop.txt
        -map 0:v:0 -map 1:a:0
        -map_metadata:g 1:g
        -vf "drawbox=x=0:y=ih-${TEXT_BORDER_H}:color=${TEXT_BOX_COLOR}:
            width=iw:height=${TEXT_BORDER_H}:t=fill,
            drawtext=fontfile=${FONT_FILE}:fontsize=${TEXT_SIZE}:
            textfile=${TEXT_SOURCE}:reload=1:fontcolor=${TEXT_COLOR}:
            x=(mod(${TEXT_SPEED}*n\\,w+tw)-tw):y=h-line_h-10,
            pad=ceil(iw/2)*2:ceil(ih/2)*2"
        -vcodec libx264
        -pix_fmt yuv420p
        -preset "${QUALITY}"
        -r "${FPS}"
        -g $((FPS * 2))
        -b:v "${VIDEO_BITRATE}"
        -acodec libmp3lame
        -ar 44100
        -threads 6
        -b:a "${AUDIO_BITRATE}"
        -flush_packets 0
        -bufsize 512k
        -f flv "${RTMP_SERVER}"
    )
    ffmpeg "${ffmpeg_options[@]}" &
}

function livestream_listen() {
    local ffmpeg_options
    livestream_log "Starting listening server."
    ffmpeg_options=(
        -hide_banner
        -loglevel error
        -listen 1
        -timeout -1
        -i "$RTMP_SERVER"
        -c:v copy
        -c:a copy
        -flags +cgop
        -g "$FPS"
        -hls_time 2
        -hls_list_size 5
        -hls_allow_cache 1
        -hls_flags delete_segments
        -flush_packets 1 ./stream.m3u8
    )
    ffmpeg "${ffmpeg_options[@]}" &
}

function livestream_manage_audio() {
    local video_text sleep_time current_file_id
    livestream_get_random_audio
    video_text=$(livestream_get_video_text "$RANDOM_AUDIO")
    livestream_update_video_text "$video_text"
    livestream_update_audio_file "$RANDOM_AUDIO" 0
    sleep_time="$AUDIO_LENGTH"
    current_file_id=1
    while true; do
        livestream_get_status
        if [[ "$STATUS" == "$STATUS_PAUSED" ]]; then
            livestream_update_audio_file "pause.opus" $current_file_id
            sleep "$sleep_time"
            livestream_get_audio_length "pause.opus"
            sleep_time="$AUDIO_LENGTH"
            video_text=$(livestream_get_video_text "pause.opus")
            livestream_update_video_text "$video_text"
            if [[ $current_file_id -eq 0 ]]; then
                current_file_id=1
            else
                current_file_id=0
            fi
        else
            livestream_get_next_audio
            livestream_update_audio_file "$NEXT_AUDIO" $current_file_id
            sleep "$sleep_time"
            sleep_time="$AUDIO_LENGTH"
            video_text=$(livestream_get_video_text "$NEXT_AUDIO")
            livestream_update_video_text "$video_text"
            if [[ $current_file_id -eq 0 ]]; then
                current_file_id=1
            else
                current_file_id=0
            fi
        fi
    done
}

function livestream_queue_pop() {
    unset 'QUEUE[0]'
    QUEUE=("${QUEUE[@]}")
    FIFO_REPLY="Popped."
}

function livestream_load_queue() {
    if [[ "$STATUS" == "$STATUS_OFFLINE" ]]; then
        livestream_log "Can't load queue: livestream is offline."              \
        "$LOG_LEVEL_WARN"
        exit 1
    fi
    echo "QUEUE" > "$FIFO_IN"
    readarray -t QUEUE < "$FIFO_OUT"
    for i in "${!QUEUE[@]}"; do
        if [[ ! -f "${QUEUE[i]}" ]]; then
            unset 'QUEUE[i]'
        fi
    done
    QUEUE=("${QUEUE[@]}")
}

function livestream_get_next_audio() {
    livestream_load_queue
    if [[ "$STATUS" == "$STATUS_STREAMING" ]]; then
        if [[ ${#QUEUE[@]} -ne 0 ]]; then
            livestream_log "Playing next audio from the queue"
            NEXT_AUDIO=${QUEUE[0]}
            livestream_remove_queue_audio "$NEXT_AUDIO"
        else
            livestream_get_random_audio
            NEXT_AUDIO=$RANDOM_AUDIO
        fi
            if [[ ! -f "$NEXT_AUDIO" ]]; then
            livestream_log "Error: audio file ($NEXT_AUDIO) not found"         \
            "$LOG_LEVEL_ERROR"
            livestream_get_random_audio
            NEXT_AUDIO=$RANDOM_AUDIO
        fi
    fi
}

function livestream_remove_queue_audio() {
    local similarity queue_audio
    if [[ $# -lt 1 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"         \
        "$LOG_LEVEL_ERROR"
        return 1
    fi
    similarity=${2:false}
    if [[ "$similarity" == true ]]; then
        queue_audio=$(find . -iname "*$1*" -print | head -n1)
    else
        queue_audio=$1
    fi
    if [[ ! -f $queue_audio ]]; then
        livestream_log "Requested audio not found." "$LOG_LEVEL_ERROR"
        FIFO_REPLY="Requested audio not found."
        return 1
    else
        livestream_log "Removing $queue_audio from queue."
    fi
    for i in "${!QUEUE[@]}"; do
        if [[ ${QUEUE[i]} = "$queue_audio" ]]; then
            unset 'QUEUE[i]'
        fi
    done
    QUEUE=("${QUEUE[@]}")
    echo "POP" > "$FIFO_IN"
    cat "$FIFO_OUT" &
    livestream_load_queue
    FIFO_REPLY="Audio successfully removed from queue."
}

function livestream_play() {
    local audio
    if [[ $# -lt 1 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"         \
        "$LOG_LEVEL_ERROR"
        return 1
    fi
    audio=$(find . -iname "*$1*" -print | head -n1)
    if [[ ! -f $audio ]]; then
        livestream_log "Requested audio not found." "$LOG_LEVEL_ERROR"
        FIFO_REPLY="Requested audio not found."
    else
        QUEUE+=("$audio")
        livestream_log "Audio $audio successfully added to queue."
        FIFO_REPLY="Audio $audio successfully added to queue."
    fi
}

function livestream_show_queue() {
    local audio
    if [[ ${#QUEUE[@]} -eq 0 ]]; then
        FIFO_REPLY="Queue is empty."
        return 1
    fi
    FIFO_REPLY="Queue:\\n"
    for audio in "${QUEUE[@]}"; do
        FIFO_REPLY+="$audio\\n"
    done
}

function livestream_get_random_audio() {
    livestream_load_music
    RANDOM_AUDIO=${MUSIC[$RANDOM % ${#MUSIC[@]}]}
    livestream_get_audio_length "$RANDOM_AUDIO"
}

function livestream_get_audio_length() {
    if [[ $# -lt 1 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"         \
        "$LOG_LEVEL_ERROR"
        return 1
    fi
    AUDIO_LENGTH=$(ffprobe -v error -show_entries format=duration -of          \
        default=noprint_wrappers=1:nokey=1 "$1")
}

function livestream_update_audio_file() {
    if [[ $# -lt 2 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"         \
        "$LOG_LEVEL_ERROR"
        return 1
    fi
    livestream_log "copying $1 into $2"
    if [[ -f "$1" ]]; then
        cp -f "$1" "./audio$2.opus"
    else
        livestream_log "Error: audio file ($1) not found." "$LOG_LEVEL_ERROR"
    fi
}

function livestream_get_video_text() {
    local audio_filename
    if [[ "$STATUS" == "$STATUS_PAUSED" ]]; then
        echo "${TEXT_PREFIX}nothing."
    else
        audio_filename=$(basename "${1%.*}")
        echo "$TEXT_PREFIX$audio_filename"
    fi
}

function livestream_update_video_text() {
    if [[ $# -lt 1 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"         \
        "$LOG_LEVEL_ERROR"
        return 1
    fi
    echo "$1" > $TEXT_SOURCE
}

function livestream_load_music() {
    local entry
    livestream_log "Loading music files."
    MUSIC=()
    for entry in "$AUDIO_DIR"/*; do
        MUSIC+=("$entry")
    done
}

function livestream_reset_video_file() {
    cat <<EOF > ./stream.m3u8
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-ALLOW-CACHE:YES
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:5.544333,
offline.ts
#EXT-X-ENDLIST
EOF
}

function livestream_quit() {
    livestream_log "Quitting livestream."
    # shellcheck disable=SC2009
    kill -9 "-$(ps -efj | grep -m 1 'livestream.sh -s' | awk '{print $4}')" && \
    livestream_reset_video_file &&                                             \
    echo "Livestream quit."
    FIFO_REPLY="Livestream stopped."
    exit
}

function livestream_pause() {
    STATUS="$STATUS_PAUSED"
    FIFO_REPLY="Livestream paused."
}

function livestream_create_loop_file() {
    cat <<EOF > ./loop.txt
ffconcat version 1.0
file audio0.opus
file audio1.opus
file loop.txt
EOF
}

function livestream_resume() {
    STATUS="$STATUS_STREAMING"
    FIFO_REPLY="Livestream resumed."
}

function livestream_log() {
    local message_log_level
    if [[ $# -lt 1 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"         \
        "$LOG_LEVEL_ERROR"
        return 1
    fi
    message_log_level="$LOG_LEVEL_INFO"
    if [[ $# -gt 1 ]]; then
        message_log_level="$2"
    fi
    if [[ ! ${LOG_LEVELS[$message_log_level]} ]]; then
        livestream_log "Error: invalid log level" "$LOG_LEVEL_ERROR"
        return 1
    fi
    if [[ "${LOG_LEVELS[$message_log_level]}" -lt "${LOG_LEVELS[$LOG_LEVEL]}"  \
    ]]; then
        return 2
    fi
    echo "$(date +'[%Y-%m-%d %H:%M:%S]') [$message_log_level] $1" >> $LOG_FILE
}

function livestream_print_status_message() {
    case "$STATUS" in
        "$STATUS_STREAMING")
            echo "Livestream is online."
            ;;
         "$STATUS_PAUSED")
            echo "Livestream is paused."
            ;;
         "$STATUS_OFFLINE")
            echo "Livestream is offline."
            ;;
    esac
}

function livestream_start() {
    if [[ "$(pgrep 'livestream.sh' | wc -l)" -gt 2 ]]; then
        livestream_log "Livestream is already running." "$LOG_LEVEL_WARN"
        echo "Livestream is already running."
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
        if read -r command < "$FIFO_IN"; then
            livestream_handle_command "$command"
        fi
        sleep 1
    done
}

function livestream_handle_command() {
    local full_command command
    if [[ $# -lt 1 ]]; then
        livestream_log "Error: missing argument(s) for ${FUNCNAME[0]}"         \
        "$LOG_LEVEL_ERROR"
        return 1
    fi
    full_command=$1
    command=$(echo "$full_command" | head -n1 | awk '{print $1;}')
    FIFO_REPLY=""
    case "$command" in
        "QUIT")
            livestream_quit
            ;;
        "STATUS")
            FIFO_REPLY=$STATUS
            ;;
        "PLAY")
            livestream_play "${full_command:5}"
            ;;
        "QUEUE")
            livestream_show_queue
            ;;
        "REMOVE")
            livestream_remove_queue_audio "${full_command:7}" true
            ;;
        "PAUSE")
            livestream_pause
            ;;
        "RESUME")
            livestream_resume
            ;;
        "POP")
            livestream_queue_pop
            ;;
        *)
            ;;
    esac
    printf '%b\n' "$FIFO_REPLY" > "$FIFO_OUT"
}

function livestream_help() {
    livestream_version
    cat <<EOF
usage: ./livestream [options]

Options:
  -h | (--)help          Displays this information.
  -v | (--)version       Displays script version.
  -s | (--)start         Starts the livestream.
  -q | (--)quit          Stops the livestream.
  -u | (--)status        Displays this livestream status.
  -p | (--)play <arg>    Plays a song if it's found.
  -w | (--)queue         Displays the queue.
  -r | (--)remove <arg>  Removes a song from the queue.
  -a | (--)pause         Pauses the livestream.
  -e | (--)resume        Resumes the livestream.
  -m | (--)pop           Pops the first element of the queue.
EOF
}

function livestream_version() {
    echo "Livestream version $SCRIPT_VERSION"
}

function livestream_send_command() {
    if [[ "$STATUS" == "$STATUS_OFFLINE" ]]; then
        livestream_log "Livestream is not running." "$LOG_LEVEL_WARN"
        echo "Livestream is not running."
        exit 1;
    fi
    case "$1" in
        "QUIT")
            echo "QUIT" > "$FIFO_IN"
            ;;
        "STATUS")
            echo "STATUS" > "$FIFO_IN"
            ;;
        "PLAY")
            echo "PLAY" "${@:2}" > "$FIFO_IN"
            ;;
        "QUEUE")
            echo "QUEUE" > "$FIFO_IN"
            ;;
        "REMOVE")
            echo "REMOVE" "${@:2}" > "$FIFO_IN"
            ;;
        "PAUSE")
            echo "PAUSE" > "$FIFO_IN"
            ;;
        "RESUME")
            echo "RESUME" > "$FIFO_IN"
            ;;
        "POP")
            echo "POP" > "$FIFO_IN"
            ;;
    esac
    cat "$FIFO_OUT"
    exit 0
}

function livestream_get_status() {
    if [[ "$(pgrep 'livestream.sh' | wc -l)" -gt 2 ]]; then
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
        "-h" | "--help" | "help")
            livestream_help
            ;;
        "-v" | "--version" | "version")
            livestream_version
            ;;
        "-s" | "--start" | "start")
            livestream_start
            ;;
        "-q" | "--quit" | "quit")
            livestream_quit
            ;;
        "-u" | "--status" | "status")
            livestream_print_status_message
            ;;
        "-p" | "--play" | "play")
            livestream_send_command "PLAY" "${@:2}"
            ;;
        "-w" | "--queue" | "queue")
            livestream_send_command "QUEUE"
            ;;
        "-r" | "--remove" | "remove")
            livestream_send_command "REMOVE" "${@:2}"
            ;;
        "-a" | "--pause" | "pause")
            livestream_send_command "PAUSE"
            ;;
        "-e" | "--resume" | "resume")
            livestream_send_command "RESUME"
            ;;
        "-m" | "--pop" | "pop")
            livestream_send_command "POP"
            ;;
        *)
            echo "Invalid argument(s). Type --help for help."
            exit 1
            ;;
    esac
}

trap livestream_quit SIGTERM
livestream_main "$@"
