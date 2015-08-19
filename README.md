# ESP8266 NODEMCU UART to MQTT bridge

## What is it

The purpose of this code is to make simple bridge between any UART enabled system (Arduino, etc) and MQTT broker.

## How it works

When you power up nodemcu the UART handling routine is initialised and waits for user input.
The desired data should be entered by sending with `\r` (carriage return) character termination at the end.
Aftere receiving `string\r` the nodemcu examines input and takes appropriate action.
The first thing to be done is to pass to nodemcu which SSID and password should be used to connect to WIFI.

After nodemcu is powered up it spits out some info at 115200 baud and then switches to 9600 where LUA interpreter executes `init.lua`. UART handling routine is then initialised which waits for SSID and WIFI password. You should send it to nodemcu like this:
```
myssid\r
wifipassword\r
```

After receiving this it tries to connect to AP and after that it should establish connection with MQTT broker. MQTT settings are hardcoded at the moment in `mqttbridge.lua` file so you MUST change variables named with MQTT* in order to connect your nodemcu to your MQTT broker installation.

nodemcu is always listening for bytes `0xf0` and `0xf3` which also must be terminated by `\r`.
If you send `0xf0` the nodemcu responds with one byte which represents status register value.
If you send `0xf3` the nodemcu reboots.
You can also send `uartstop\r` which removes UART handling routine currently in place and returns you back to the LUA interpreter.

After successful connection to MQTT broker nodemcu subscribes to `clients/cmds` and `dev/nodemcu/sub` topics. It also publishes its presence on topic `clients` saying `hi nodemcu 192.168.x.y`. IP address is replaced with its IP address on your network. It also informs MQTT broker with last will and testament of stating `bye nodemcu` on topic `clients`. Nodemcu reponds to `uptime` command on `clients/cmd` topic. It responds with `pong nodemcu 192.168.x.y` back to `clients` topic.
UART handler is also passing the receiving data from uart to MQTT topic `dev/nodemcu/pub`. If anything is received on `dev/nodemcu/sub` it is passed to UART. The first byte it sends out on UART is always status register value.

Status register bits explanation:
```
rrrmwwaaa

rrr - reserved / unused
m   - 1 if MQTT is connected, 0 otherwise
ww  - 00 waiting for ssid and wifi password (after poweron / reboot)
    - 01 got ssid, waiting for wifi password
    - 11 got ssid, got wifi password
aaa - convert these bits to decimal and see the wifi.sta.status() return values - https://github.com/nodemcu/nodemcu-firmware/wiki/nodemcu_api_en#wifistastatus
```

For example:
```
000111101 means: connected to MQTT broker, got SSID, got wifi password, STATION_GOT_IP
000000101 means: connected to AP but waiting for SSID and wifi password input, not connected to MQTT broker. This happens after reboot.
```

Code is written in such manner that it should reconnect if connection to MQTT broker goes offline for some reason. It also reconnects if WIFI AP disappears and appears later. I tried this.

## Prerequisites

-lua firmware on nodemcu / esp8266
-tool to upload .lua files

Note: after uploading `mqttbridge.lua` you must compile it because `init.lua` executes `mqttbridge.lc` file after succesful connection with WIFI AP.

Please report when you encounter unwanted behaviour :)

