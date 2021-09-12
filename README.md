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
**Important: note: since all the files are concatenated on the fly, they all must
use the same codec!**

### Nginx
This is left as an exercise for the user.

### Offline video
To create a video that will be displayed everytime your stream is offline, you
can use the following commands.
For videos:
```shell
ffmpeg -i VIDEO -c:v libx264 -t 5 -pix_fmt yuv420p offline.ts 
```
For images:
```shell
ffmpeg -loop 1 -i IMAGE -c:v libx264 -t 5 -pix_fmt yuv420p offline.ts 
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

## TODO
- [ ] Music queue
- [ ] Installation
- [ ] Start / stop + queue (using signals?)
