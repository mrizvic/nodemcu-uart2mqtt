CLIENTID = "nodemcu"
MQTTRECONNECT = true
SUBTOPIC = "dev/" .. CLIENTID .. "/sub"
PUBTOPIC = "dev/" .. CLIENTID .. "/pub"
PRESENCE_TOPIC = "clients"
PRESENCE_TOPIC_CMD = "clients/cmd"
MQTTSRV = '192.168.168.168'
MQTTPORT = 1883
MQTTUSER = 'nodemcu'
MQTTPASS = 'mcunode'
MQTT_CONNECTED_FLAG=5
UART_TERMINATOR='\r'

tmr.alarm(4, 2000, 1, function()
    if bit.isclear(mqttStatus, MQTT_CONNECTED_FLAG) and MQTTRECONNECT then
        mqtt_connect()
    end
end)

m = mqtt.Client(CLIENTID, 15, MQTTUSER, MQTTPASS)

m:lwt(PRESENCE_TOPIC, "bye ".. CLIENTID, 0, 0)

m:on("connect", function(conn)
    -- this event seems dead but its documented so...
    mqttStatus=bit.set(mqttStatus,MQTT_CONNECTED_FLAG)
end )

m:on("offline", function(conn)
    mqttStatus=bit.clear(mqttStatus,MQTT_CONNECTED_FLAG)
    uart.on("data", UART_TERMINATOR, function(data)
        uart.write(0, status)
        local s = string.gsub(data, UART_TERMINATOR, "") -- remove line breaks
        if s == 'uartstop' then
            uart.on('data')
        elseif string.byte(s,1) == 0xf0 then
            -- continue
        elseif string.byte(s,1) == 0xf3 then
            node.restart()
        else
        end
    end, 0)
end )

m:on("message", function(conn, topic, data)
  if data == 'uartstop' then
    uart.on('data')
    m:publish(PUBTOPIC, "uartstop", 0, 0, function(conn)
        MQTTRECONNECT=false
        m:close()
    end )
    return    
  elseif data == 'uptime' then
    m:publish(PUBTOPIC, "tmr.now()=" .. tmr.now(), 0, 0, function(conn) end )
  elseif data == 'ping' and topic == PRESENCE_TOPIC_CMD then
    m:publish(PRESENCE_TOPIC, "pong " .. CLIENTID .. " " .. wifi.sta.getip(), 0, 0, function(conn) end )
  elseif data ~= nil then
      uart.write(0, status, data)
  end
end )

mqtt_connect = function ()
    -- if not connected then
    if bit.isclear(mqttStatus,MQTT_CONNECTED_FLAG) then 
        m:connect(MQTTSRV, MQTTPORT, 0, function(conn)
            m:subscribe(SUBTOPIC, 0, function(conn) end )
            m:subscribe(PRESENCE_TOPIC_CMD, 0, function(conn) end )
            m:publish(PRESENCE_TOPIC, "hi " .. CLIENTID .. " " .. wifi.sta.getip(), 0, 0, function(conn) end )
            uart.on("data", UART_TERMINATOR, function(data)
                uart.write(0, status)
                local s = string.gsub(data, UART_TERMINATOR, "") -- remove line breaks
                if s == 'uartstop' then
                    uart.on('data')
                    MQTTRECONNECT=false
                    m:close()
                elseif string.byte(s,1) == 0xf0 then
                    -- continue
                elseif string.byte(s,1) == 0xf3 then
                    MQTTRECONNECT=false
                    m:close()
                    node.restart()
                else
                    m:publish(PUBTOPIC, s, 0, 0, function(conn) end )
                end
            end, 0)
            mqttStatus=bit.set(mqttStatus,MQTT_CONNECTED_FLAG)
        end)
    else
    end
end
