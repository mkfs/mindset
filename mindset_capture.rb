#!/usr/bin/env ruby
# Receive data from bluetooth and print to stdout
# assumes /dev/rfcomm0 if device is not provided
# Note: this does not perform SPP connect

require 'rubygems'                    # gem install serialport
require 'serialport'
require 'json/ext'

DEFAULT_SERIAL_PORT = "/dev/rfcomm0"
BT_SYNC = 0xAA

class EndOfTransmissionError < RuntimeError; end
class ByteNotReceivedError < RuntimeError; end
class ConnectionTimeoutError < RuntimeError; end

def parse_packet(buf)
  hex = []
  buf.bytes.each { |c| hex << "%02X" % c }
  puts hex.join(' ')
end

def read_n_bytes(conn, n)
  bytes = []
  n.times { bytes << conn.readbyte }
  bytes.join ''
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

  plen = wait_for_not_byte(conn, BT_SYNC, 100)
  # if PLEN >= BT_SYNC, packet is invalid
  if plen >= BT_SYNC
    return
  end

  buf = read_n_bytes(conn, plen)
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
      read_packet bt

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
