#!/usr/bin/env ruby
# Ruby module for reading data from a Neurosky Mindset.
# (c) Copyright 2013 mkgs@github http://github.com/mkfs/mindset                 
# License: BSD http://www.freebsd.org/copyright/freebsd-license.html

require 'rubygems'                    # gem install serialport
require 'serialport'
require 'json/ext'

# ----------------------------------------------------------------------
module Mindset

=begin rdoc
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
        pkt.decode_data_row(excode, code, value, verbose)
        packets << pkt
      end

      packets
    end

    def self.decode(excode, code, value, verbose=false)
      Packet.new.decode(excode, code, value, verbose)
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

    # Treat 3-element array as a 3-byte integer in big-endian order
    # Note: This zero-pads the integer to 4-bytes before calling unpack, which
    #       may not be correct if the values can be signed.
    def unpack_3byte_bigendian(arr)
      arr.unshift(0).pack('cccc').unpack('L>').first
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
=end
  class Connection < SerialPort
    SERIAL_PORT = "/dev/rfcomm0"
    BAUD_RATE = 57600
    BT_SYNC = 0xAA

    class TimeoutError < RuntimeError; end

    def initialize(device=nil)
      @device = device || SERIAL_PORT
      super @device, BAUD_RATE
    end

    def read_n_bytes(n)
      bytes = []
      n.times { bytes << self.readbyte }
      bytes
    end

    def while_not_byte(val, &block)
      cont = true
      while cont
        c = self.readbyte
        break if c == val
        cont = yield c
      end
    end

    def wait_for_not_byte(val, max_counter=6000)
      counter = 0
      c = nil
      while counter < max_counter
        c = self.readbyte
        break if (c != val)
        counter += 1
        sleep 0.1
      end

      raise TimeoutError if counter >= max_counter
      c
    end

    def wait_for_byte(val, max_counter=6000)
      counter = 0
      while counter < max_counter
        c = self.readbyte
        break if (c == val)
        counter += 1
        sleep 0.1
      end

      raise TimeoutError if counter >= max_counter
    end

    def read_packet(verbose=false)
      wait_for_byte(BT_SYNC, 100)
      wait_for_byte(BT_SYNC, 100)

      plen = read_n_bytes(1).first
      if plen >= BT_SYNC
        $stderr.puts "Invalid packet size: #{plen} bytes" if verbose
        return []
      end

      buf = read_n_bytes(plen)

      buf_cs = buf.inject(0) { |sum, b| sum + b } & 0xFF
      buf_cs = ~buf_cs & 0xFF
      checksum = read_n_bytes(1).first
      if buf_cs != checksum
        $stderr.puts "Packet #{buf_cs} != checksum #{checkum}" if verbose
        return []
      end

      Packet.parse buf, verbose
    end

    def disconnect
      self.close
    end
  end

  # ----------------------------------------------------------------------
  def self.connect(device, verbose=false)
    $stderr.puts "CONNECT #{device}, #{MINDSET_BAUD}" if verbose
    begin
      return Connection.new device
    rescue TypeError => e
      $stderr.puts "Could not connect to #{device}: #{e.message}"
      nil
    end
  end

end
