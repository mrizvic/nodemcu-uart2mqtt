t={}
c=0
status=0
mqttStatus=0
ssidStatus=0
SSID_RECEIVED=3
WIFIPASSWORD_RECEIVED=4
UART_TERMINATOR='\r'

tmr.alarm(1, 333, 1, function()
    status=wifi.sta.status()
    status=bit.bor(status,mqttStatus,ssidStatus)
end)

uart.on("data", UART_TERMINATOR, function(data)
    uart.write(0, status)
    local s = string.gsub(data, UART_TERMINATOR, "") -- remove termination character
    if s == 'uartstop' then
    -- return to lua interpreter
        uart.on('data')
    elseif string.byte(s,1) == 0xf0 then
        -- continue
    -- restart
    elseif string.byte(s,1) == 0xf3 then
        node.restart()
    -- read and store SSID
    elseif c == 0 then
        t[c]=s
        c=c+1
        ssidStatus=bit.set(ssidStatus,SSID_RECEIVED)
    -- read and store WIFI passphrase, connect to AP, exec MQTT script
    elseif c == 1 then
        t[c]=s
        c=c+1
        ssidStatus=bit.set(ssidStatus,WIFIPASSWORD_RECEIVED)
        wifi.sta.config(t[0],t[1])
        wifi.sta.autoconnect(1)
        tmr.alarm(2, 200, 1, function()
            if wifi.sta.getip()== nil then
            else
                tmr.stop(2)
                dofile('mqttbridge.lc')
                tmr.alarm(3,500,0, function()
                    mqtt_connect()
                end)
            end
        end)

    end
end, 0)
