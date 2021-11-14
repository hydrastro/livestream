# livestream
Livestream radio made easy with ffmpeg, thanks to @ottersarecool and noxy!

## Dependencies
This scripts has the following dependencies:
- `ffmpeg`
- `nginx`

Which can be easily installed with these commands:
- Ubuntu/Debian: `sudo apt install ffmpeg nginx`
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
**You can skip this if you are already familiar with nginx or other
webservers.**  
For starting nginx you simply do:
```shell
sudo service nginx start
```
For making it autostart at boot:
```shell
systemctl enable nginx
```
You need to set up a root dir for the livestream service, it may be a root dir
of an existing nginx service or you could create a new one as you like.  
We decided to go for `/srv/stream` you are free to choose whatever path you
prefer!
```shell
sudo mkdir /srv/stream
```
This directory will be owned by root, and that's bad: we need to change the
owner to the user nginx runs with, in this example it's the Debian default nginx
user `www-data`.
```shell
sudo chown -R www-data:www-data /srv/stream/
```
Next you want to add a new server block to your `nginx.conf` located at
`/etc/nginx/services/sites-available`.
```shell
sudo nano /etc/nginx/services/sites-available
```
You could edit the `default` configuration or create a new one, in that case
don't forget to link it to `sites-available`:
```shell
ln -s /etc/nginx/sites-available/yourconfig /etc/nginx/sites-enabled/yourconfig
```
The configuration could be something like this
```
server {
    listen [::]:80;        # Listens on port 80 for IPV6
    listen 80;             # Listens on port 80 for IPV4
    server_name localhost; # This is your server name. it can be your domain
    index index.html;      # This is the default file nginx will look for
    root /srv/stream;      # Your webroot

    # If you want to make your recordings public and accessible by anyone:
    location /vods {
        autoindex on;
    }
}
```
You can test your config with:
```shell
nginx -t
```
If your output is this, you are mostly good to go!
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```
Finally reload the nginx config:
```shell
nginx -s reload
```
You're done! Your nginx server should now listen on port 80.  
You can access it by simply visiting http://localhost.  

#### Want HTTPS?
Get [Certbot](https://certbot.eff.org/instructions) and follow the
instructions.  

### Want to stream over rtmps?
If you want to stream encrypted all you need to do is to add a few more lines to
your nginx configuraiton file, **outside the http context!**  
Our advice is to let the stream server only run on localhost, so that nginx
establishes unencrypted connections only for connections between the same
server!
```
stream {
    server {
        listen 1935 ssl;
        proxy_pass 127.0.0.1:6645; # This port should match the one you choose
        proxy_buffer_size 32k;
        ssl_certificate /etc/letsencrypt/live/your.domain.tld/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/your.domain.tld/privkey.pem;
    }
}
```

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
### Start
Here's how you run the script:
```shell
./livestream.sh -s
```

### Stop
For stopping the script:
```shell
./livestream.sh -q
```

### Status
For checking the script status:
```shell
./livestream.sh -u
```

### Systemd Service
You can create a new systemd service, with which you could automate the script
start and more easily (for example at system boot, or making it restart in case
of possible failures).  
Before installing the service you should check the unit file `stream.service` to
see if the working directory and running user are correct.  
```shell
nano stream.service
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
sudo systemctl enable stream
```

## Contributing
Feel free to contribute, pull requests are always welcome.  
Please reveiw and clean your code with `shellcheck` before pushing it.  
If you want to help, Here below is a todo list.

## TODO
- [ ] MP4 / webm (no js) stream
- [ ] Commands regex
- [ ] Playlists
- [X] Music queue
- [X] Pause
- [X] Proper logging (levels)
