require 'faye/websocket'
require 'eventmachine'
require 'json'
module Buttplug

  class Client
=begin rdoc
Creates a new client for buttplug.io

Arguments:
* serverLocation (string) - Where our buttplug.io server is hosted. this will tend to be: <code>"wss://localhost:12345/buttplug"</code>

Returns:
* A shiney new buttplug client ready for some action
=end
    def initialize(serverLocation)
      @location=serverLocation
      #Ok Explanation time!
      # * @EventQueue - The events we are triggering on the server, Expected to be an array, with the first element being the message Id, and the second being the message itself!
      # * @responseQueue - And our messages back from the server! Will be an array with the 
      @eventQueue=EM::Queue.new
      @eventMachine=Thread.new{EM.run{
        eventQueue=@eventQueue 
        messageWatch={}
        ws = Faye::WebSocket::Client.new(@location)
        ws.on :open do |event|
          p [Time.now, :open]
          ws.send '[{"RequestServerInfo": {"Id": 1, "ClientName": "roboMegumin", "MessageVersion": 1}}]'
        end
        ws.on :message do |event|
          message=JSON::parse(event.data)[0]
          message.each{|key,value|
            #We don't really care about the key just yet ... We are going to just care about finding our ID
            if(messageWatch.keys.include?(value["Id"]))
              messageWatch[value["Id"]]<<{key => value}#And now we care about our key!
              puts messageWatch[value["Id"]].object_id
              messageWatch.delete(value["Id"])
              p [Time.now, :message_recieved, [{key => value}]]
              next
            elsif(key=="ServerInfo")
              p [Time.now, :server_info, value]
            end
          }
        end
        ws.on :close do |event|
          p [Time.now, :close, event.code, event.reason]
          ws = nil
        end
        EM.add_periodic_timer(0.5){
          ws.send "[{\"Ping\": {\"Id\": #{generateID()}}}]"
          eventQueue.pop{|msg|
            ws.send msg[1]
            messageWatch[msg[0]]=msg
            p [Time.now, :message_send, msg[1]] 
          }
        }
      }}
      @eventMachine.run
    end
=begin rdoc
Tells our server to start scanning for new devices
=end
    def startScanning()
      id=generateID()
      @eventQueue.push([id,"[{\"StartScanning\":{\"Id\":#{id}}}]"])
    end
=begin rdoc
Tells our server to stop scanning for new devices
=end
    def stopScanning()
      id=generateID()
      @eventQueue.push([id,"[{\"StopScanning\":{\"Id\":#{id}}}]"])
    end
=begin rdoc
Lists all devices available to the server

Returns:
* An array of available devices from the server

Example:
    client.listDevices()
       [{"DeviceName"=>"XBox Compatible Gamepad (XInput)", "DeviceIndex"=>1, "DeviceMessages"=>{"SingleMotorVibrateCmd"=>{}, "VibrateCmd"=>{"FeatureCount"=>2}, "StopDeviceCmd"=>{}}}]
=end  
    def listDevices()
      id=generateID()
      deviceRequest=[id,"[{\"RequestDeviceList\": {\"Id\":#{id}}}]"]
      @eventQueue.push(deviceRequest)
      while(deviceRequest.length<3) do
        sleep 0.01#Just so we arn't occupying all the time on the system while we are waiting for our device list to come back.
      end
      return deviceRequest[2]["DeviceList"]["Devices"]
    end
=begin rdoc
Sends a message to our buttplug server

Arguments:
* message (JSON formatted string) - The message we are sending to our server

Returns:
* the Response from our server 
=end
    def sendMessage(message)
      @eventQueue.push(message)
      while(message.length<3) do
        sleep 0.01
      end
      return message[3]
    end
=begin rdoc
Does exactly what it says on the tin, generates a random id for our messages

Returns:
* a number between 2 and 4294967295
=end
    def generateID()
      return rand(2..4294967295)
    end
  end
  class Device
=begin rdoc
Creates our Device wrapper for our client

Note: This does create a few functions on the fly. you should check to see if they are available using  .methods.include

Arguments:
* client (Buttplug::Client) - Our buttplugrb client that we are gonna use to control our device
* deviceInfo (Hash) - Our information that we should have fetched from the list_devices() instance method ... should look like:
     {"DeviceName"=>"XBox Compatible Gamepad (XInput)", "DeviceIndex"=>1, "DeviceMessages"=>{"SingleMotorVibrateCmd"=>{}, "VibrateCmd"=>{"FeatureCount"=>2}, "StopDeviceCmd"=>{}}}

Returns:
* Our nicely bundled up device ready to be domminated~
=end
    def initialize(client, deviceInfo)
      #Ok we are gonna expect our deviceInfo to be a Hash so we can do some ... fun things ...
      #{"DeviceName"=>"XBox Compatible Gamepad (XInput)", "DeviceIndex"=>1, "DeviceMessages"=>{"SingleMotorVibrateCmd"=>{}, "VibrateCmd"=>{"FeatureCount"=>2}
      @deviceName=deviceInfo["DeviceName"]
      @deviceIndex=deviceInfo["DeviceIndex"]
      @client=client
      #Ok so we are starting our weird metaProgramming BS here
      if(deviceInfo["DeviceMessages"].keys.include? "VibrateCmd")
        @vibeMotors=deviceInfo["DeviceMessages"]["VibrateCmd"]["FeatureCount"]
        define_singleton_method(:vibrate){|speeds|
          #And now the real fun, we are gonna craft our message!
          id=client.generateID()
          cmd=[{"VibrateCmd"=>{"Id"=>id,"DeviceIndex"=>@deviceIndex,"Speeds"=>[]}}]
          #Ok we arn't gonna really care about how many speeds we are fed in here, we are gonna make sure that our total array isn't empty.
          (0..@vibeMotors-1).each{|i|
            if speeds[i].nil?
              speeds[i]=0
            end 
            cmd[0]["VibrateCmd"]["Speeds"]<<{"Index"=>i,"Speed"=>speeds[i]}
          }
          client.sendMessage([id,cmd.to_json])
        }
        define_singleton_method(:vibrateAll){|speed|
          speeds=[]
          (0..@vibeMotors-1).each{|i|
            speeds<<speed
          }
          vibrate(speeds)
        }
      end
    end
##
# :method: vibrate
#
# Vibrates the motors on the device!
#
# Arguments:
# * speeds (Array - Float) - Array of speeds, any extra speeds will be dropped, and any ommitted speeds will be set to 0

##
# :method: vibrateAll
#
# Vibrates all motors on the device
#
# Arguments:
# * speed (Float) - The speed that all motors on the device to be set to
  end
end