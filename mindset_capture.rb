#!/usr/bin/env ruby
# Receive data from bluetooth and print to stdout
# assumes /dev/rfcomm0 if device is not provided
# Note: this does not perform SPP connect

require 'rubygems'                    # gem install serialport
require 'serialport'
require 'json/ext'

DEFAULT_SERIAL_PORT = "/dev/rfcomm0"
BT_SYNC = 0xAA
EXCODE = 0x55
CODE_SIGNAL_QUALITY = 0x02 # POOR_SIGNAL quality 0-255
CODE_ATTENTION = 0x04      # ATTENTOON eSense 0-100
CODE_MEDITATION = 0x05     # MEDITATION eSense 0-100
CODE_BLINK = 0x16          # BLINK strength 0-255
CODE_WAVE = 0x80           # RAW wave value: 2-byte big endian twos-complement
CODE_ASIC_EEG = 0x83       # ASIC EEG POWER 8 3-byte big-endian integers

class EndOfTransmissionError < RuntimeError; end
class ByteNotReceivedError < RuntimeError; end
class ConnectionTimeoutError < RuntimeError; end

def unpack_asic_eeg(arr)
  { :delta => arr[0,3].unshift(0).pack('cccc').unpack('L>').first,
    :theta => arr[3,3].unshift(0).pack('cccc').unpack('L>').first,
    :lo_alpha => arr[6,3].unshift(0).pack('cccc').unpack('L>').first,
    :hi_alpha => arr[9,3].unshift(0).pack('cccc').unpack('L>').first,
    :lo_beta => arr[12,3].unshift(0).pack('cccc').unpack('L>').first,
    :hi_beta => arr[15,3].unshift(0).pack('cccc').unpack('L>').first,
    :lo_gamma => arr[18,3].unshift(0).pack('cccc').unpack('L>').first,
    :mid_gamma => arr[21,3].unshift(0).pack('cccc').unpack('L>').first
    }
end

def decode_data_row(excode, code, value)
  # note: currently, excode is ignored
  case code
  when CODE_SIGNAL_QUALITY
    { :signal_quality => value.first }
  when CODE_ATTENTION
    { :attention => value.first }
  when CODE_MEDITATION
    { :meditation => value.first }
  when CODE_BLINK
    { :blink => value.first }
  when CODE_WAVE
    { :wave => value[0,2].join('').unpack("s>") }
  when CODE_ASIC_EEG
    unpack_asic_eeg(value[0,24])
  else
    $stderr.puts "Unrecognized code: %02X" % code
  end
end

def parse_packet(bytes)
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
    packets << decode_data_row(excode, code, value)
  end

  packets
end

def read_n_bytes(conn, n)
  bytes = []
  n.times { bytes << conn.readbyte }
  bytes
end

def while_not_byte(conn, val, &block)
  cont = true
  while cont
    c = conn.readbyte
    # raise EndOfTransmissionError if EOF
    break if c == val
    cont = yield c
  end
end

def wait_for_not_byte(conn, val, max_counter=6000)
  counter = 0
  c = nil
  while counter < max_counter
    c = conn.readbyte
    break if (c != val)
    #raise ByteNotReceivedError if ...
    # raise EndOfTransmissionError if EOF
    counter += 1
    sleep 0.1
  end

  raise ConnectionTimeoutError if counter >= max_counter
  c
end

def wait_for_byte(conn, val, max_counter=6000)
  counter = 0
  while counter < max_counter
    c = conn.readbyte
    break if (c == val)
    #raise ByteNotReceivedError if ...
    # raise EndOfTransmissionError if EOF
    counter += 1
    sleep 0.1
  end

  raise ConnectionTimeoutError if counter >= max_counter
end

def read_packet(conn)
  # two BT_SYNCs in a row mean the packet wll follow
  wait_for_byte(conn, BT_SYNC, 100)
  wait_for_byte(conn, BT_SYNC, 100)

  plen = read_n_bytes(conn, 1).first
  return if plen >= BT_SYNC

  buf = read_n_bytes(conn, plen)

  buf_cs = buf.inject(0) { |sum, b| sum + b } & 0xFF
  buf_cs = ~buf_cs & 0xFF
  checksum = read_n_bytes(conn, 1).first
  if buf_cs != checksum
    $stderr.puts "packet did not pass checksum"
    return
  end

  parse_packet buf
end

MINDSET_BAUD = 57600
def read_bt_data(file)
  baud = 57600
  $stderr.pputs "CONNECT #{file}, #{MINDSET_BAUD}" if $DEBUG
  bt = SerialPort.new file, MINDSET_BAUD
  # catch TypeError --> invalid port

  cont = true
  # this is a simple protocol: just start reading packets
  while cont
    begin
      puts read_packet(bt).inspect

    rescue ByteNotReceivedError, EndOfTransmissionError => e
      cont = 0
    end
  end
end

if __FILE__ == $0
  port = ARGV.first
  port ||= DEFAULT_SERIAL_PORT

  read_bt_data(port)
end
