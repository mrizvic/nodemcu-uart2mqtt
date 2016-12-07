-- variables
wificfg={}
STATUS_REGISTER=0
STATUS_REGISTER_TEMP=0
MQTT_REGISTER=0
SSID_REGISTER=0
GOT_IP_FLAG=3
SSID_RECEIVED_FLAG=4
WIFIPASSWORD_RECEIVED_FLAG=5
MQTT_CONNECTED_FLAG=6
UART_TERMINATOR1='\r'
UART_TERMINATORS='[\r\n]'

MYMAC=wifi.sta.getmac()
-- split MAC address into two strings without colons
MYMACA=string.sub(MYMAC,0,2) .. string.sub(MYMAC,4,5) .. string.sub(MYMAC,7,8)
MYMACB=string.sub(MYMAC,10,11) .. string.sub(MYMAC,13,14) .. string.sub(MYMAC,16,17)

MQTTCLIENTID = "nodemcu" .. MYMACB
MQTTSRV = 'mqtt.dmz6.net'
MQTTPORT = 1883
MQTTUSER = nil
MQTTPASS = nil                     
MQTTRECONNECT=false
-- dont set MQTTKEEPALIVE too low!
MQTTKEEPALIVE=15
MQTTKEEPALIVETOPIC='dummy'
RXTOPIC = "dev/" .. MQTTCLIENTID .. "/rx"
TXTOPIC = "dev/" .. MQTTCLIENTID .. "/tx"
BCASTTOPIC = "clients"
CMDTOPIC = "clients/cmd"

-- setup ESP8266 as WIFI client
wifi.setmode(wifi.STATION)

-- update status register periodicaly
tmr.alarm(1, 250, 1, function()
    STATUS_REGISTER=wifi.sta.status()
    STATUS_REGISTER=bit.bor(STATUS_REGISTER, MQTT_REGISTER, SSID_REGISTER)
    -- send update
    if STATUS_REGISTER_TEMP ~= STATUS_REGISTER then
        uart.write(0, STATUS_REGISTER, UART_TERMINATOR1)
    end
    STATUS_REGISTER_TEMP=STATUS_REGISTER
end)

-- try to reconnect to MQTT if not connected
tmr.alarm(2, 5000, 1, function()
    if bit.isclear(MQTT_REGISTER, MQTT_CONNECTED_FLAG) and MQTTRECONNECT then
        mqtt_connect()
    end
end)

tmr.alarm(4, (MQTTKEEPALIVE-1)*1000, 1, function()
    if bit.isset(MQTT_REGISTER, MQTT_CONNECTED_FLAG) then
        m:publish(MQTTKEEPALIVETOPIC,'.', 0, 0, function(conn) end )
    end
end)

-- initialise custom UART handler
-- be careful as this steals LUA interpreter
uart.on("data", UART_TERMINATOR1, function(data)
    -- uart.write(0, STATUS_REGISTER, UART_TERMINATOR1)
    local s = string.gsub(data, UART_TERMINATORS, "") -- remove termination characters
    if s == 'uartstop' then
        -- return to lua interpreter
        uart.on('data')
        -- close MQTT connection
        if bit.isset(MQTT_REGISTER, MQTT_CONNECTED_FLAG) then
            MQTTRECONNECT=false
            m:close()
        end
    elseif string.byte(s,1) == 0xf0 then
        -- dont pass to MQTT
    elseif string.byte(s,1) == 0xf3 then
        -- disconnect from MQTT and restart
        uart.on('data')
        if bit.isset(MQTT_REGISTER, MQTT_CONNECTED_FLAG) then
            MQTTRECONNECT=false
            m:close()
        end
        node.restart()
    -- read and store SSID
    elseif bit.isclear(SSID_REGISTER, SSID_RECEIVED_FLAG) then
        wificfg.ssid=s
        SSID_REGISTER=bit.set(SSID_REGISTER, SSID_RECEIVED_FLAG)
    -- read and store WIFI passphrase, connect to AP, exec MQTT script
    elseif bit.isclear(SSID_REGISTER, WIFIPASSWORD_RECEIVED_FLAG) then
        wificfg.pwd=s
        SSID_REGISTER=bit.set(SSID_REGISTER, WIFIPASSWORD_RECEIVED_FLAG)
        wifi.sta.config(wificfg.ssid, wificfg.pwd)
        wifi.sta.autoconnect(1)
        tmr.alarm(3, 200, 1, function()
            if wifi.sta.getip()== nil then
            else
                tmr.stop(3)
                SSID_REGISTER=bit.set(SSID_REGISTER, GOT_IP_FLAG)
                -- set reconnect flag and let tmr.alarm(2, ...) kick in
                MQTTRECONNECT=true
            end
        end)
    elseif bit.isset(MQTT_REGISTER, MQTT_CONNECTED_FLAG) then
        m:publish(TXTOPIC, s, 0, 0, function(conn) end )
    else
        -- uh-oh?
        uart.write(0, 'undefined error', UART_TERMINATOR1)
    end
    uart.write(0, STATUS_REGISTER, UART_TERMINATOR1)
end, 0)

-- initialise mqtt_connect() function, client object and events
mqtt_connect = function ()
    -- if not connected then
    if bit.isclear(MQTT_REGISTER, MQTT_CONNECTED_FLAG) then 
        m:connect(MQTTSRV, MQTTPORT, 0, function(conn)
            m:subscribe(RXTOPIC, 0, function(conn) end )
            m:subscribe(CMDTOPIC, 0, function(conn) end )
            m:publish(BCASTTOPIC, "hi " .. MQTTCLIENTID .. " " .. wifi.sta.getip(), 0, 0, function(conn) end )
            MQTT_REGISTER=bit.set(MQTT_REGISTER, MQTT_CONNECTED_FLAG)
            -- uart.write(0, STATUS_REGISTER, data, UART_TERMINATOR1)
        end)
    else
    end
end

m = mqtt.Client(MQTTCLIENTID, MQTTKEEPALIVE, MQTTUSER, MQTTPASS)

-- last will and testament
m:lwt(BCASTTOPIC, "bye ".. MQTTCLIENTID, 0, 0)

-- event handlers
m:on("connect", function(conn)
    -- this event seems dead but its documented so...
    MQTT_REGISTER=bit.set(MQTT_REGISTER, MQTT_CONNECTED_FLAG)
end)

m:on("offline", function(conn)
    MQTT_REGISTER=bit.clear(MQTT_REGISTER, MQTT_CONNECTED_FLAG)
end)

m:on("message", function(conn, topic, data)
  -- respond to 'ping' and 'heap' otherwise pass to UART after status register
  if data == 'ping' and topic == CMDTOPIC then
    m:publish(BCASTTOPIC, "pong " .. MQTTCLIENTID .. " " .. wifi.sta.getip(), 0, 0, function(conn) end )
  elseif data == 'heap' and topic == CMDTOPIC then
    m:publish(BCASTTOPIC, "heap " .. MQTTCLIENTID .. " " .. node.heap(), 0, 0, function(conn) end )
  elseif data ~= nil and topic == RXTOPIC then
      uart.write(0, STATUS_REGISTER, data, UART_TERMINATOR1)
  end
end)
