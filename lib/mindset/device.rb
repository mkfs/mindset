#!/usr/bin/env ruby
# :title: Mindset::Device
# = Mindset::Device
# DRb Object that manages a Neurosky Mindset 
# (c) Copyright 2014 mkfs@github http://github.com/mkfs/mindset                 
# License: BSD http://www.freebsd.org/copyright/freebsd-license.html

require 'drb'

require 'rubygems'
require 'json/ext'

require 'mindset/connection'

$MINDSET_DEBUG=true


module Mindset

=begin rdoc
DRb service which manages a Neurosky Mindset device.
=end
  class Device

=begin rdoc
Timeout for connection attempt, in tenths of a second.
=end
    TIMEOUT = 600
    SERIAL_PORT = "/dev/rfcomm0"

=begin rdoc
URI that the DRb service for this device is listening on.
=end
    attr_accessor :uri

=begin rdoc
SerialPort connection to headset. This is a Mindset::Device object.
=end
    attr_reader :connection
    alias :conn :connection

=begin rdoc
Connect to a Bluetooth serial device.
=end
    def connect(device, &block)
      @connection = Connection.connect(device || SERIAL_PORT, $MINDSET_DEBUG,
                                       &block)
      @connection.start
    end

=begin rdoc
Disconnect from the Bluetooth serial device
=end
    def disconnect
      @connection.disconnect
      @connection = nil
    end

=begin rdoc
Return true if serial port is connected to a headset
=end
    def connected?
      @connection && @connection.connected?
    end

=begin rdoc
Wrapper that delegates to Connection#read_packet.
=end
    def read_packet_buffer
      @connection && @connection.read_packet_buffer
    end

    # ----------------------------------------------------------------------
    # DRB Service
    
=begin rdoc
Start a DRb service for listening to a Neurosky Mindset device. The service
runs in a new process. 
This returns a the URI to the DRb service for the Mindsky::Device object.
=end
    def self.start
      $stderr.puts "Starting Mindset::Device ..." if $MINDSET_DEBUG

      pipe_r, pipe_w = IO.pipe
      pid = fork do
        pipe_r.close
        start_service(self.new, pipe_w)
      end

      pipe_w.close
      buf = pipe_r.read
      uri = Marshal.load(buf)
      pipe_r.close

      Process.detach(pid)

      obj = connect_or_die uri

      $stderr.puts "Mindset::Device on #{uri} PID #{pid}" if $MINDSET_DEBUG

      return(obj)
    end

=begin rdoc
Return true if service is running.
=end
    def running?
      @uri
    end

=begin rdoc
Stop the DRb service.
=end
    def stop
      $stderr.puts "Stopping #{uri}..." if $MINDSET_DEBUG
      DRb.stop_service 
      @uri = nil
      $stderr.puts "Mindset::Device stopped" if $MINDSET_DEBUG
    end

=begin rdoc
Start Drb service. This writes the URI of the service to one end of a pipe.
=end
    def self.start_service(obj, pipe_w)
      DRb.start_service(nil, obj)
      uri = DRb.uri
      obj.uri = uri

      Marshal.dump(uri, pipe_w)
      pipe_w.flush
      pipe_w.close

      trap('HUP') do
        puts 'Stopping Mindset service' if $MINDSET_DEBUG 
        DRb.stop_service
        puts 'Starting Mindset service' if $MINDSET_DEBUG
        DRb.start_service(uri, obj) 
      end
      
      trap('INT') do
        puts 'Stopping Mindset service' if $MINDSET_DEBUG
        DRb.stop_service 
      end

      DRb.thread.join
    end

    private

    def self.connect_or_die(uri)
      obj = nil

      TIMEOUT.times do
        begin                                                                   
          obj = DRb::DRbObject.new_with_uri(uri)
          obj.to_s  # method call to force connection
          break
        rescue DRb::DRbConnError
          sleep 0.1
        end
      end

      raise DRbConnectionError.new("Cannot connect to #{uri}") if ! obj

      obj
    end
  end

end

# ----------------------------------------------------------------------
# Sample client code:
if __FILE__ == $0

  server = Mindset::Device.start

  # ... do something here ...
  sleep 5

  server.stop
end
