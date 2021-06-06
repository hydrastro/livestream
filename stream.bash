#!/bin/bash
#ffmpeg stream script
#made for public domain use by noxy
#Thanks to spaghetti for giving me the ffmpeg line and inspiring me to actually put this all together a bit better for myself and for others! Thanks man!
#FUCK EVILCORPS

IP="[::]/0.0.0.0"   #Change me! If using rtmps, change this to 127.0.0.1
PORT="6645"
STREAMKEY="changeme"
FPS="60"

#Twitch Settings
TWITCHKEY="<your stream key>"
TWITCHSRV="rtmp://fra02.contribute.live-video.net/app/"

#Stream without recording
#ffmpeg -listen 1 -i rtmp://"$IP":"$PORT"/stream/"$STREAMKEY" -c:v copy -c:a copy -flags +cgop -g "$FPS" -hls_time 2 -hls_list_size 5 -hls_allow_cache 1 -hls_flags delete_segments -flush_packets 1 stream.m3u8; \cp -f done.m3u8 stream.m3u8;

#Stream with recording
#ffmpeg -listen 1 -i rtmp://"$IP":"$PORT"/stream/"$STREAMKEY" -c:v copy -c:a copy -flags +cgop -g "$FPS" -hls_time 2 -hls_list_size 5 -hls_allow_cache 1 -hls_flags delete_segments -flush_packets 1 stream.m3u8 -f segment -c:v copy -c:a copy -strftime 1 -segment_time 1000000000 -segment_format mp4 'vods/%Y-%m-%d_%H-%M-%S_vod.mp4'; \cp -f done.m3u8 stream.m3u8;

#Twitch relay (unencrypted)
#ffmpeg -listen 1 -i rtmp://"$IP":6645/stream/"$STREAMKEY" -c:v copy -c:a copy -flags +cgop -g 60 -hls_time 2 -hls_list_size 5 -hls_allow_cache 1 -hls_flags delete_segments -flush_packets 1 stream.m3u8 -f flv -vcodec libx264 "$TWITCHSRV""$TWITCHKEY" -f segment -c:v copy -c:a copy -strftime 1 -segment_time 1000000000 -segment_format mp4 'vods/%Y-%m-%d_%H-%M-%S_vod.mp4'; \cp -f done.m3u8 stream.m3u8;
