#!/usr/bin/env ruby
# :title: Mindset::Connection
# = Mindset::Connection
# (c) Copyright 2014 mkfs@github http://github.com/mkfs/mindset                 
# License: BSD http://www.freebsd.org/copyright/freebsd-license.html

require 'thread'

require 'rubygems'                    # gem install serialport
require 'serialport'

require 'mindset/packet'

module Mindset

=begin rdoc
A connection to a Mindset device. This wraps the SerialPort connection to the
device. Device must already be paired and have a serial bluetooth connection
established.
=end
  class Connection < SerialPort

    SERIAL_PORT = "/dev/rfcomm0"
    BAUD_RATE = 57600
    BT_SYNC = 0xAA

    class TimeoutError < RuntimeError; end

=begin rdoc
Return a Mindset::Connection object for device.
If a block is provided, this yields the Connection object, then disconnects it
when the block returns.
=end
    def self.connect(device, verbose=false, &block)
      begin

        conn = self.new device, BAUD_RATE
        # Note: SerialPort does not call initialize()
        conn.init_connection(device, verbose)

        if block_given?
          yield conn
          conn.disconnect
        else
          return conn
        end

      rescue TypeError => e
        $stderr.puts "ERROR: Could not connect to #{device}: #{e.message}"
      end
      nil
    end

    def init_connection(device, verbose)
      @running_mutex = Mutex.new
      @buffer_mutex = Mutex.new

      @device = device || SERIAL_PORT
      @verbose = verbose
      self.read_timeout = 100

      $stderr.puts "CONNECT #{device}, #{BAUD_RATE}" if @verbose

      @buffer = []
      @connected = true
      @running = false
    end

=begin rdoc
Disconnect from device
=end
    def disconnect
      stop
      sleep 0.01
      self.close
      @connected = false
    end

=begin rdoc
Return true if serial port is connected.
=end
    def connected?
      @connected
    end

    def start
      @running_mutex.synchronize { @running = true }

      while running?
        pkts = read_packet
        @buffer_mutex.synchronize { @buffer.concat pkts } if (! pkts.empty?)
        Thread.pass
      end
    end

    def stop
      @running_mutex.synchronize { @running = false }
    end

    def running?
      @running_mutex.synchronize { @running }
    end

=begin rdoc
Return an Array of Packet objects.
Note: this will perform a blocking read on the serial device.
=end
    def read_packet

      pkts = []
      if wait_for_byte(BT_SYNC) and wait_for_byte(BT_SYNC)
        plen = getbyte
        if plen and plen < BT_SYNC
          pkts = read_payload(plen)
        else
          $stderr.puts "Invalid packet size: #{plen} bytes" if @verbose
        end
      end
      pkts
    end

    def read_packet_buffer
      @buffer_mutex.synchronize {
        pkts = @buffer
        @buffer = []
        pkts
      }
    end

    private

    def read_payload(plen)
      str = self.read(plen)
      buf = str ? str.bytes.to_a : []

      checksum = getbyte

      buf_cs = buf.inject(0) { |sum, b| sum + b } & 0xFF
      buf_cs = ~buf_cs & 0xFF
      if (! checksum) or buf_cs != checksum
        $stderr.puts "Packet #{buf_cs} != checksum #{checksum}" if @verbose
        return []
      end

      pkts = Packet.parse buf
    end

    def wait_for_byte(val, max_counter=10)
      max_counter.times do 
        c = self.getbyte
        return true if (c == val)
        sleep 0.01
      end
      false
    end

  end

=begin rdoc
A fake Mindset connection which just replays data previously captured (and
serialized to JSON).  This is used to provide a uniform interface for 
displaying either realtime or captured EEG data.

Note: This expects a PacketStore object to be stored in @data before read_packet
is called.
=end
  class LoopbackConnection

=begin rdoc
PacketStore object containing captured EEG data.
=end
    attr_accessor :data

    def initialize(data=nil, verbose=false)
      @data = data
      @counter = 0
      @wave_idx = 0
      @esense_idx = 0
      @verbose = verbose
    end

=begin rdoc
Simulate a read of the Mindset device by returning an Array of Packet objects.
This assumes it will be called 8 times a second.

According to the MDT, Mindset packets are sent at the following intervals:
  1 packet per second: eSense, ASIC EEG, POOR_SIGNAL
  512 packets per second: RAW

Each read will therefore return 64 RAW packets. Every eighth read will also 
return 1 eSense, ASIC_EEG, and POOR_SIGNAL packet.
=end
    def read_packet_buffer
      packets = @data[:wave][@wave_idx, 64].map { |val| 
                Packet.factory(:wave, val)  }
      @wave_idx += 64
      @wave_idx = 0 if @wave_idx >= @data[:wave].count

      if @counter == 7
        packets << Packet.factory(:delta, @data[:delta][@esense_idx])
        packets << Packet.factory(:theta, @data[:theta][@esense_idx])
        packets << Packet.factory(:lo_alpha, @data[:lo_alpha][@esense_idx])
        packets << Packet.factory(:hi_alpha, @data[:hi_alpha][@esense_idx])
        packets << Packet.factory(:lo_beta, @data[:lo_beta][@esense_idx])
        packets << Packet.factory(:hi_beta, @data[:hi_beta][@esense_idx])
        packets << Packet.factory(:lo_gamma, @data[:lo_gamma][@esense_idx])
        packets << Packet.factory(:mid_gamma, @data[:mid_gamma][@esense_idx])
        packets << Packet.factory(:signal_quality, 
                                  @data[:signal_quality][@esense_idx])
        packets << Packet.factory(:attention, @data[:attention][@esense_idx])
        packets << Packet.factory(:meditation, @data[:meditation][@esense_idx])
        packets << Packet.factory(:blink, @data[:blink][@esense_idx])
        @esense_idx += 1
        @esense_idx = 0 if @esense_idx >= @data[:delta].count
      end

      @counter = (@counter + 1) % 8
      packets
    end

    def disconnect
      @data = {}
    end
  end
end
