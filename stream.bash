#!/bin/bash

IP="[::]"
STREAMKEY="mIzV2zBlhVFMOYzHuVjWWOHDU9xrdwzWDFzElu4G"

ffmpeg -listen 1 -i rtmp://"$IP":6645/stream/"$STREAMKEY" -c:v copy -c:a copy -flags +cgop -g 60 -hls_time 2 -hls_list_size 1 -hls_allow_cache 1 -hls_flags delete_segments -flush_packets 1 stream.m3u8; \cp -f done.m3u8 stream.m3u8;
