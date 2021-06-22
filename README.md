# Easy self hosted livestream using ffmpeg

See Twitch and YouTube cry, no mercy for evil corps!

<img src="https://raw.githubusercontent.com/ottersarecool/livestream/master/2021-06-22_18-51.png">

# TL;DR
Pull this repo, point your webserver to the location of the pulled files, modify `stream.bash` to your liking, copy the service file if desired to your systemd folder, start and enable it, stream with obs to your own rtmp server!

# Requirements
Required tools: `ffmpeg` `obs-studio` & `nginx`

# Packages

- Ubuntu/Debian:   `apt install ffmpeg obs-studio nginx`

- Arch Linux:     `pacman -S ffmpeg obs-studio nginx`

# Setting up NGINX

**You can skip this if you are already familiar with NGINX or other webservers.**

`systemctl start nginx && systemctl enable nginx`

Create a directory that acts as the root for your stream, in this case I use `/srv/stream` you are free to choose whatever path you like!

`mkdir /srv/stream`
This directory will be owned by root, make sure to correct this and change the owner to the user your nginx runs with, in this example `http`

`chown -R http:http /srv/stream/`

Next you want to add a new server block to your `nginx.conf` _located at `/etc/nginx`_

It could be something like this

```
server {
    listen [::]:80;             #   Listens on port 80 for IPV6
    listen 80;                  #   Listens on port 80 for IPV4
    server_name localhost;      #   This is your server name, can be your domain for example
    index index.html;           #   Nginx will look by default in /srv/stream for the file index.html
    root /srv/stream;           #   Your webroot

    location /vods {
        #If you want to make your recordings public and accessible by anyone
        autoindex on;
    }
}
```
Test your config with

`nginx -t`

If you can read this you are mostly good to go!
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Finally reload the config
`nginx -s reload`

Your NGINX should now listen on port 80 and returning a 404 page

Check http://localhost in your browser or via `curl`

`curl http://localhost` _This should simply return 404_

Now move all the files in this repo to your webroot and visit your site again.

# Want HTTPS?
Get [Certbot](https://certbot.eff.org/instructions) and follow the instructions

After successful installation do:

`certbot --nginx`

Select your domain, congrats you now have https for your domain!

# Also want to stream over rtmps?
If you want to stream encrypted all you need to do in addition is to add a few lines to your `/etc/nginx/nginx.conf` **outside the http context!**

My advice is to let the stream server only run on localhost 127.0.0.1 so only nginx makes connections to it unencrypted on the same server!
```
stream {
    server {
        listen 1935 ssl;
        proxy_pass 127.0.0.1:6645;
        proxy_buffer_size 32k;
        ssl_certificate /etc/letsencrypt/live/your.domain.tld/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/your.domain.tld/privkey.pem;
    }
}
```

# Starting the ffmpeg RTMP(s) server
There are two ways on how to do it:
- execute `stream.bash` by hand everytime you want to stream
- use the `stream.service` file and have it run in the background at all times so you don't have to manually restart it once you end your stream (very useful tbh)

#### The by hand way
_this needs to be done everytime you want to stream!_

```
$ bash stream.bash
```

#### The based way
First: make sure to modify the paths in the service to match your paths, otherwise it will not work!
```
$ cp stream.service /etc/systemd/system/stream.service
$ systemctl start stream
$ systemctl status stream
#If you want to have it automatically started everytime you boot do:
$ systemctl enable stream
```

# The stream.bash file
This file is the core, it spawns a rtmp server that awaits your input

Change the `IP` and `STREAMKEY` variables to your liking, in my example it's `[::]` which means listen on all ipv6 addresses, you can enter `0.0.0.0` for example `0.0.0.0` means it's listening on all ipv4 addresses or change this to whatever your public ip is.

I suggest to use `127.0.0.1` if you plan on streaming via rtmps!

`PORT` is the port ffmpeg will listen to, you can freely change it or keep the default value

The `STREAMKEY` variable can be treated as your personal access token to this endpoint, make it hard to guess to increase security

`FPS` defines the frames per second your stream runs at, should match the fps you set up in your obs

There are two ways on how you can stream, one is without recording your stream and the other is with recording your stream.

If you choose to record your stream make a directory in your webroot called `vods` and make sure it's also owned by `http`

# Offline video
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

# Webchat

https://github.com/ottersarecool/websocket-livechat

# OBS configuration
Now you need to setup your OBS to actually make use of your cool streaming server.

Make a new profile, name it BASED or something like that

Go to `Settings -> Stream -> Service -> Custom`

## If you have a rtmp configuration (unencrypted)

In the Server field enter: `rtmp://<IP>:<PORT>/stream/<STREAMKEY>`

## If you have it via rtmps

In the server field enter: `rtmps://your.domain.tld:1935/stream/<STREAMKEY>`

Leave the Stream Key field blank

Hit Apply

**_Start Streaming_**

That's basically it! Fuck Twitch and YouTube and any other commercial rule cuck website, be your own streaming service! Make the rules yourself, stream whatever the fuck you want!

Enjoy!

# use ffmpeg to stream to ffmpeg
You can stream any file supported by ffmpeg to ffmpeg

On your pc you could add this function to your `.bashrc` and use it like this:

stream `<file>` `<audio track id>`
    
`stream file.mp4 0`

```
function stream() {
        ffmpeg -re -i $1 -c:v libx264 -profile:v main -preset:v medium \
                -r 30 -g 60 -keyint_min 60 -sc_threshold 0 -b:v 2500k -maxrate 2500k -map 0:v:0 \
                -bufsize 6000k -pix_fmt yuv420p -g 60 -c:a aac -b:a 160k -ac 2 -map 0:a:$2 \
                -ar 44100 -f flv rtmps://<server>
}
```

Assuming the file has subtitles embedded

```
function streamanime() {
        #usage streamanime "file.mkv" 0[subitle track id] 0[audio track id]
        ffmpeg -i $1 -map 0:s:$2 $1.ass        
        ffmpeg -re -i "$1" -c:v libx264 -profile:v main -preset:v medium \
                -r 30 -g 60 -keyint_min 60 -sc_threshold 0 -b:v 2500k -maxrate 2500k -map 0:v:0 -vf "ass='$1.ass'" \           
                -bufsize 6000k -pix_fmt yuv420p -g 60 -c:a aac -b:a 160k -ac 2 -map 0:a:$3 \
                -ar 44100 -f flv rtmps://<server>
}
```
:^)

Font used: https://github.com/source-foundry/Hack
