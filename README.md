# How to stream with ffmpeg

See Twitch and YouTube cry

You will need `ffmpeg` and `obs` and preferably a server where you have shell access to and on that server a webserver like `nginx`

on ubuntu `sudo apt install ffmpeg obs nginx` find if the package is available for your distro or compile it yourself

This also werks on Windows and Android!

ffmpeg is used to spawn the rtmp server and process your video input

obs is used for actually streaming to the rtmp server

nginx is used to actually serve the created m3u8 playlist

```
ffmpeg -listen 1 -i 'rtmp://0.0.0.0:6645/stream/test12345' -c:v copy -c:a copy  -flags +cgop -g 60 -hls_time 1 -hls_list_size 20 -hls_allow_cache 1 -hls_flags delete_segments stream.m3u8; \cp -f done.m3u8 stream.m3u8;
```

0.0.0.0 means it's listening on all ipv4 addresses, change this to whatever your ip is

This command does most of the magic it spawns the rtmp server and waits for user input

the cp command is useful if you want to display a offline video for example if you are not streaming

To make a video for when your stream is offline do the following

`ffmpeg -i file.{png,webm/mp4 whatever} -t 5 blah.ts`

this will create a 5 second long ts file 

next create a file named `done.m3u8` and add the following contents to it

```
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-ALLOW-CACHE:YES
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:5.544333,
blah.ts
#EXT-X-ENDLIST
```

This will be displayed everytime your stream is not online

If you want to have a chat included on your based twitch you can embed any webirc or webchat you want, it's up to you! In my example I use the n0xy.net webirc but you are free to modify it to your needs or use n0xy.net

That's basically it! Fuck Twitch and YouTube and any other commercial rule cuck website, be your own streaming service!
