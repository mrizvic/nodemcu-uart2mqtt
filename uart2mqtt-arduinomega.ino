// undefine this if WIFI settings are hardcoded into nodemcu lua script
#define ESP_INIT

// WIFI settings to pass towards esp
#define SSIDNAME  "MySSID"
#define SSIDPASS  "WIFIpassword"

// line separator - this must match UART_TERMINATOR1 definition from nodemcu lua script
#define UART_TERMINATOR1  '\r'

// baudrate towards computer (USB) and towards esp
#define USB_BAUDRATE  115200
#define ESP_BAUDRATE  115200

// restart nodemcu each time arduino is restarted
#define ESP_RESTART

// define if you want detailed explanation over USB of STATUS_REGISTER from nodemcu
#undef DEBUG_SREG_VERBOSE

// define both lines if nodemcu needs to manually run lua script
#undef ESP_RUNSCRIPT_NAME  uart2mqtt-R3.lua
#undef ESP_RUNSCRIPT

// reserve MAX_MSGLEN bytes in arduino RAM for receiving content
#define MAX_MSGLEN  128

// periodically send data to esp (in milliseconds)
unsigned long interval = 1000;

// stop unless you want to modify the code :)

int x = 0;

static String content1 = "";
static String content2 = "";

const byte ledPin = LED_BUILTIN;

static char sreg = 0;

static unsigned long previousMillis = 0;
static unsigned long currentMillis = 0;

static boolean connected = 0;

void esp_restart() {
  // reboot esp
  Serial.println("rebooting esp...");
  Serial.flush();
  Serial1.write(0xf3);
  Serial1.write(UART_TERMINATOR1);

  // Serial.findUntil() function returns true if the
  // target string is found and false if it times out
  // wait for LUA prompt
  // Serial1.setTimeout(1000);
  while (!Serial1.find('> '));

  Serial.print(content1);
  Serial.flush();

  delay(500);
}

void esp_init() {
  Serial.println("passing WIFI credentials to esp...");
  Serial.flush();
  Serial1.println(SSIDNAME);
  Serial1.flush();
  delay(10);

  Serial1.println(SSIDPASS);
  Serial1.flush();
  delay(10);

  // wait until IP address is obtained and connected to MQTT
  Serial.println("Waiting for init to complete");
  while (sreg != 0x7d) {
    Serial.print(".");
    delay(100);
    // wait for STATUS_REGISTER and UART_TERMINATOR1 to arrive from esp
    if (Serial1.available() > 0) {
      content1 = Serial1.readStringUntil(UART_TERMINATOR1);
      if (content1.charAt(0) != sreg) {
        sreg = content1.charAt(0);
        debugStatusRegister(sreg);
      }
    }
  }
  content1 = "";
  content2 = "";
  connected = 1;
  Serial.println("esp init done");
}

void setup() {
  // dont expect incoming messages to be longer than MAX_MSGLEN
  content1.reserve(MAX_MSGLEN);
  content2.reserve(MAX_MSGLEN);

  pinMode(ledPin, OUTPUT);

  // Serial = USB (console)
  // Serial1 = tx1/rx1 - esp
  Serial.begin(USB_BAUDRATE);
  Serial1.begin(ESP_BAUDRATE);

  // wait for serial hardware to finish setup
  while (!Serial);
  while (!Serial1);

  // check if esp is present and whats its status
  Serial.println("polling esp status...");
  Serial.println("0xfd");
  Serial1.write(0xfd);
  Serial.println("UART_TERMINATOR1");
  Serial1.write(UART_TERMINATOR1);

  // read SREG or timeout after setTimeout() period
  content1 = Serial1.readStringUntil(UART_TERMINATOR1);
  sreg = content1.charAt(0);
  debugStatusRegister(sreg);
  // if not connected and stuff then restart and init
  if (sreg != 0x7d) {

#ifdef ESP_RESTART

    esp_restart();
    
#endif

#ifdef ESP_RUNSCRIPT
    // lua dofile - start uart2mqtt script
    Serial.println("dofile(\"ESP_RUNSCRIPT_NAME\")\r\n");
    Serial1.println("dofile(\"ESP_RUNSCRIPT_NAME\")\r\n");
    Serial1.flush();
    delay(100);
#endif

#ifdef ESP_INIT

    /*
      at this point esp will try to:
        - connect to AP
        - obtain IP address from DHCP
        - connect to MQTT broker
        - publish last-will-and-testament message to BCASTTOPIC
        - subscribe to RXTOPIC
        - subscribe to CMDTOPIC
        - publish IP address to BCASTTOPIC


    */
    esp_init();

#endif
  }

  Serial.println("Entering loop...");
  Serial.flush();

}

void loop() {

  currentMillis = millis();

  // read analog value from pin A5

  if ( (currentMillis - previousMillis) > interval ) {
    Serial.print("!");
    if (connected) {
      x = analogRead(5);
      // send to esp
      Serial1.print(x);
      Serial1.write(UART_TERMINATOR1);
      Serial1.flush();
      // print on usb console
      Serial.print(">");
      Serial.println(x);
      Serial.flush();
    }
    previousMillis = currentMillis;
  }

  // read SREG + anything? until UART_TERMINATOR1
  if (Serial1.available()) {
    content1 = Serial1.readStringUntil(UART_TERMINATOR1);

    if (content1.charAt(0) != sreg) {
      Serial.print("SREG change from: ");
      Serial.println(sreg, HEX);
      sreg = content1.charAt(0);
      debugStatusRegister(sreg);
    }

    // pass to usb if there is anything more than just SREG
    if (content1.length() > 1) {
      content1 = content1.substring(1);
      Serial.print("CONTENT1=");
      Serial.println(content1);
      Serial.flush();
    }
  }

  // if STATUS_REGISTER suggests that we are not connected anymore then disable sending data from arduino to esp
  if ( (connected) && (sreg != 0x7d) ) {
    connected = 0;
    Serial.println("disconnected");
    if (sreg == 5) {
      Serial.println("sreg == 5, esp restarted?");
      esp_init();
    }
  } else if ( (!connected) && (sreg != 0x7d) ) {
    if (sreg == 5) {
      Serial.println("sreg == 5, esp restarted?");
      esp_init();
    }
  } else if ( (!connected) && (sreg == 0x7d) ) {
    // enable sending data if esp reconnects
    connected = 1;
    Serial.println("connected");
  }

  // did we receive anything from internet?
  if (content1 == "1") {
    digitalWrite(ledPin, HIGH);
  } else if (content1 == "0") {
    digitalWrite(ledPin, LOW);
  }

  content1 = "";

  // read from usb and pass to esp
  if (Serial.available()) {
    content2 = Serial.readStringUntil(UART_TERMINATOR1);
  }

  if (content2 != "") {
    if (content2 == "STATUS") {
      Serial1.write(0xf0);
      Serial1.write(UART_TERMINATOR1);
    } else if (content2 == "REBOOT") {
      Serial1.write(0xf3);
      Serial1.write(UART_TERMINATOR1);
    } else {
      Serial1.print(content2);
      Serial1.write(UART_TERMINATOR1);
      Serial1.flush();
    }
    content2 = "";
  }

}

int debugStatusRegister (char sreg) {
  Serial.print("SREG=");
  Serial.println(sreg, HEX);

#ifdef DEBUG_SREG_VERBOSE
  char s1;
  s1 = sreg & 7;
  Serial.print("wifi.sta.status()=");
  if (s1 == 0) {
    Serial.println("STATION_IDLE");
  }
  else if (s1 == 1) {
    Serial.println("STATION_CONNECTING");
  }
  else if (s1 == 2) {
    Serial.println("STATION_WRONG_PASSWORD");
  }
  else if (s1 == 3) {
    Serial.println("STATION_NO_AP_FOUND");
  }
  else if (s1 == 4) {
    Serial.println("STATION_CONNECT_FAIL");
  }
  else if (s1 == 5) {
    Serial.println("STATION_GOT_IP");
  }
  Serial.print("wifi.sta.getip()= ");
  Serial.println((sreg & 8) >> 3);
  Serial.print("SSID_RECEIVED_FLAG= ");
  Serial.println((sreg & 16) >> 4);
  Serial.print("WIFIPASSWORD_RECEIVED_FLAG= ");
  Serial.println((sreg & 32) >> 5);
  Serial.print("MQTT_CONNECTED_FLAG= ");
  Serial.println((sreg & 64) >> 6);
  Serial.println();
  Serial.flush();
#endif

}
