#!/usr/bin/env ruby
# Ruby module for reading data from a Neurosky Mindset.
# (c) Copyright 2013 mkfs@github http://github.com/mkfs/mindset                 
# License: BSD http://www.freebsd.org/copyright/freebsd-license.html

require 'rubygems'                    # gem install serialport
require 'serialport'
require 'json/ext'

# ----------------------------------------------------------------------
module Mindset

=begin rdoc
Collection of captured Packet objects. Packets are collected by type. The 
start and end timestamps are saved.
=end
  class PacketStore < Hash
    def initialize
      super

      self[:start_ts] = Time.now
      self[:end_ts] = nil
      self[:delta] = []
      self[:theta] = []
      self[:lo_alpha] = []
      self[:hi_alpha] = []
      self[:lo_beta] = []
      self[:hi_beta] = []
      self[:lo_gamma] = []
      self[:mid_gamma] = []
      self[:signal_quality] = []
      self[:attention] = []
      self[:meditation] = []
      self[:blink] = []
      self[:wave] = []
    end

    def to_json
      super
    end

  end

  # ----------------------------------------------------------------------
=begin rdoc
A Mindset data packet.
This is usually either a Raw data packet, an eSense packet, or an ASIC EEG
packet.
=end
  class Packet < Hash
    EXCODE = 0x55              # Extended code
    CODE_SIGNAL_QUALITY = 0x02 # POOR_SIGNAL quality 0-255
    CODE_ATTENTION = 0x04      # ATTENTION eSense 0-100
    CODE_MEDITATION = 0x05     # MEDITATION eSense 0-100
    CODE_BLINK = 0x16          # BLINK strength 0-255
    CODE_WAVE = 0x80           # RAW wave value: 2-byte big-endian 2s-complement
    CODE_ASIC_EEG = 0x83       # ASIC EEG POWER 8 3-byte big-endian integers

    # returns array of packets
    def self.parse(bytes, verbose=false)
      packets = []
      while not bytes.empty?
        excode = 0
        while bytes[0] == EXCODE
          excode += 1
          bytes.shift
        end

        code = bytes.shift
        vlen = (code >= 0x80) ? bytes.shift : 1
        value = bytes.slice! 0, vlen
        pkt = Packet.new
        pkt.decode(excode, code, value, verbose)
        packets << pkt
      end

      packets
    end

    def self.decode(excode, code, value, verbose=false)
      Packet.new.decode(excode, code, value, verbose)
    end

    def self.factory(name, value)
      pkt = self.new
      pkt[name.to_sym] = value
      pkt
    end

    def decode(excode, code, value, verbose=nil)
      # note: currently, excode is ignored
      case code
      when CODE_SIGNAL_QUALITY
        self[:signal_quality] = value.first
      when CODE_ATTENTION
        self[:attention] = value.first
      when CODE_MEDITATION
        self[:meditation] = value.first
      when CODE_BLINK
        self[:blink] = value.first
      when CODE_WAVE
        self[:wave] = value[0,2].join('').unpack("s>").first
      when CODE_ASIC_EEG
        unpack_asic_eeg(value[0,24])
      else
        $stderr.puts "Unrecognized code: %02X" % code if verbose
      end
      self
    end

    def is_asic_wave?
      ([:lo_beta, :hi_beta, :delta, :lo_gamma, :theta, :mid_gamma, :lo_alpha, 
        :hi_alpha] & self.keys).count > 0
    end

    def is_esense?
      (self.keys.include? :attention) || (self.keys.include? :meditation)
    end

    def to_json
      super
    end

    private

    # Treat 3-element array as a 3-byte unsigned integer in little-endian order
    def unpack_3byte_bigendian(arr)
      arr.push(0).pack('cccc').unpack('L<').first
    end

    def unpack_asic_eeg(arr)
      self[:delta] = unpack_3byte_bigendian(arr[0,3])
      self[:theta] = unpack_3byte_bigendian(arr[3,3])
      self[:lo_alpha] = unpack_3byte_bigendian(arr[6,3])
      self[:hi_alpha] = unpack_3byte_bigendian(arr[9,3])
      self[:lo_beta] = unpack_3byte_bigendian(arr[12,3])
      self[:hi_beta] = unpack_3byte_bigendian(arr[15,3])
      self[:lo_gamma] = unpack_3byte_bigendian(arr[18,3])
      self[:mid_gamma] = unpack_3byte_bigendian(arr[21,3])
    end
  end

  # ----------------------------------------------------------------------
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

    def initialize(device=nil)
      @device = device || SERIAL_PORT
      super @device, BAUD_RATE
      # Note: Mutex causes crashes when used with qtbindings
      @locked = false
    end

=begin rdoc
Return an Array of Packet objects.
Note: this will perform a blocking read on the serial device.
=end
    def read_packet(verbose=false)
      return [] if @locked
      @locked = true

      pkts = []
      if wait_for_byte(BT_SYNC) and wait_for_byte(BT_SYNC)
        plen = self.getbyte
        if plen and plen < BT_SYNC
          pkts = read_payload(plen, verbose)
        else
          $stderr.puts "Invalid packet size: #{plen} bytes" if verbose
        end
      end
      @locked = false
      pkts
    end

    def disconnect
      self.close
    end

    private

    def read_payload(plen, verbose=false)
      str = self.read(plen)
      buf = str ? str.bytes.to_a : []

      checksum = self.getbyte

      buf_cs = buf.inject(0) { |sum, b| sum + b } & 0xFF
      buf_cs = ~buf_cs & 0xFF
      if (! checksum) or buf_cs != checksum
        $stderr.puts "Packet #{buf_cs} != checksum #{checkum}" if verbose
        return []
      end

      pkts = Packet.parse buf, verbose
    end

    def wait_for_byte(val, max_counter=500)
      max_counter.times do 
        c = self.getbyte
        return true if (c == val)
      end
      false
    end
  end

=begin rdoc
A fake Mindset connection which just replays data previously captured (and
serialized to JSON).
This is used to provide a uniform interface for displaying either realtime or
captured EEG data.
Note: This expects a PacketStore object to be stored in @data before read_packet
is called.
=end
  class LoopbackConnection
    attr_accessor :data

    def initialize(data=nil)
      @data = data
      @counter = 0
      @wave_idx = 0
      @esense_idx = 0
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
    def read_packet(verbose=false)
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

  # ----------------------------------------------------------------------
=begin rdoc
Return a Mindset::Connection object for device.
If a block is provided, this yields the Connection object, then disconnects it
when the block returns.
=end
  def self.connect(device, verbose=false, &block)
    $stderr.puts "CONNECT #{device}, #{MINDSET_BAUD}" if verbose
    begin
      conn = Connection.new device
      if block_given?
        yield conn
        conn.disconnect
      else
        return conn
      end
    rescue TypeError => e
      $stderr.puts "Could not connect to #{device}: #{e.message}"
    end
    nil
  end

end
