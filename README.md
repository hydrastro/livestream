# livestream
Livestream radio made easy with ffmpeg, thanks to @ottersarecool and noxy!

## Dependencies
This scripts has the following dependencies:
- `ffmpeg`
- `nginx`

Which can be easily installed with these commands:
- Ubuntu/Debian: `apt install ffmpeg nginx`
- Arch: `pacman -S ffmpeg nginx`

## Installation
### livestream.sh
The first thing you have to do is edit your configs in `livestream.sh`:
```shell
nano livestream.h
```
Then you should add some music files to `/music`.
*Important: note: since all the files are concatenated on the fly, they all must
use the same codec!*

-`IP` is the listening ip address, it can be set also to your public ip address.
-`PORT` is the port ffmpeg will listen to, you can freely change it or keep the
default value
-`STREAMKEY` variable can be treated as your personal access token to this
endpoint, make it hard to guess to increase security
-`FPS` defines the frames per second your stream runs at
-`FPS`="30"
-`VIDEO_SOURCE` is the video file that will be looped over the whole stream
-`FONT_FILE` is the font used for the texts displayed on the stream
-`TEXT_PREFIX` is the prefix of the text displayed on the stream
-`TEXT_SPEED` sets how fast should the "currently playing" text move
-`TEXT_SIZE` is the size of the text
-`TEXT_BOX_COLOR` is the text background color, you can also set it's opacity,
for example `black@0.5`
-`TEXT_BORDER_W` indicates the height of the text background
-`QUALITY` indicates the preset (speed and compression ratio) of the ffmpeg
stream, it can be set to `superfast`, `veryfast`, `faster`, `fast`, `medium`,
`slow`, `slower`, `veryslow`, `placebo`
-`VIDEO_BITRATE` is the bitrate of the video
-`AUDIO_BITRATE` is the bitrate of the audio

### Nginx
This is left as an exercise for the user.

### Offline video
To create a video that will be displayed everytime your stream is offline, you
can use the following command:
```shell
ffmpeg -i INPUTFILE -t 5 -y offline.ts
```

## Usage
### Manual
Here's how you run the script manually:  
```shell
nohup ./livestream.sh & disown
```
### Systemd Service
Alternatively, you can create a new systemd service, which handles the script
restart in case of failures.  
Before installing the service you should check if the working directory and the
user are correct.  
```shell
sudo cp stream.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo service stream start
```
Then for starting the stream can simply type:
```shell
sudo service stream status
```
or, for reading the full log:
```shell
sudo journalctl -u stream.service
```
If you want to have it automatically started everytime you boot do:
```shell
systemctl enable stream
```

