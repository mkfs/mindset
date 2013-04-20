#!/usr/bin/env ruby
# Receive data from bluetooth and print to stdout
# assumes /dev/rfcomm0 if device is not provided

require 'ostruct'
require 'optparse'

require 'rubygems'                    # gem install serialport
require 'serialport'
require 'json/ext'

# ----------------------------------------------------------------------
DEFAULT_SERIAL_PORT = "/dev/rfcomm0"
MINDSET_BAUD = 57600

BT_SYNC = 0xAA
EXCODE = 0x55

CODE_SIGNAL_QUALITY = 0x02 # POOR_SIGNAL quality 0-255
CODE_ATTENTION = 0x04      # ATTENTION eSense 0-100
CODE_MEDITATION = 0x05     # MEDITATION eSense 0-100
CODE_BLINK = 0x16          # BLINK strength 0-255
CODE_WAVE = 0x80           # RAW wave value: 2-byte big endian twos-complement
CODE_ASIC_EEG = 0x83       # ASIC EEG POWER 8 3-byte big-endian integers

class ConnectionTimeoutError < RuntimeError; end

# ----------------------------------------------------------------------
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

def decode_data_row(excode, code, value, verbose=nil)
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
    $stderr.puts "Unrecognized code: %02X" % code if verbose
  end
end

def parse_packet(bytes, verbose=false)
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
    packets << decode_data_row(excode, code, value, verbose)
  end

  packets
end
# ----------------------------------------------------------------------
def packets_to_json( h, options )
  # TODO: something more sophisticated
  h.to_json
end

def new_packet_store
  { 
    :start_ts => Time.now,
    :end_ts => nil,
    :delta => [],
    :theta => [],
    :lo_alpha => [],
    :hi_alpha => [],
    :lo_beta => [],
    :hi_beta => [],
    :lo_gamma => [],
    :mid_gamma => [],
    :signal_quality => [],
    :attention => [],
    :meditation => [],
    :blink => [],
    :wave => []
  }
end

def store_packets( h, packets, options )
  h[:end_ts] = Time.now
  packets.each { |pkt| pkt.each { |k,v| h[k] << v } }
end

def print_packets( packets, options )
  label = options.multi || options.verbose
  packets.each do |pkt|
    pkt.each { |k,v| puts "%s%d" % [(label ? k.to_s.upcase + ': ' : ''), v] }
  end
end

# ----------------------------------------------------------------------
def read_n_bytes(conn, n)
  bytes = []
  n.times { bytes << conn.readbyte }
  bytes
end

def while_not_byte(conn, val, &block)
  cont = true
  while cont
    c = conn.readbyte
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
    counter += 1
    sleep 0.1
  end

  raise ConnectionTimeoutError if counter >= max_counter
end

def read_packet(conn, verbose=false)
  wait_for_byte(conn, BT_SYNC, 100)
  wait_for_byte(conn, BT_SYNC, 100)

  plen = read_n_bytes(conn, 1).first
  if plen >= BT_SYNC
    $stderr.puts "Invalid packet size: #{plen} bytes" if verbose
    return []
  end

  buf = read_n_bytes(conn, plen)

  buf_cs = buf.inject(0) { |sum, b| sum + b } & 0xFF
  buf_cs = ~buf_cs & 0xFF
  checksum = read_n_bytes(conn, 1).first
  if buf_cs != checksum
    $stderr.puts "Packet #{buf_cs} != checksum #{checkum}" if verbose
    return []
  end

  parse_packet buf, verbose
end

def read_bt_data(options)
  $stderr.puts "CONNECT #{options.device}, #{MINDSET_BAUD}" if options.verbose
  bt = nil
  begin
    bt = SerialPort.new options.device, MINDSET_BAUD
  rescue TypeError => e
    $stderr.puts "Could not connect to #{options.device}: #{e.message}"
    return
  end

  h_pkt = new_packet_store
  num = 0
  cont = true
  while cont
    begin
      packets = read_packet(bt, options.verbose)
      num += packets.length
      if options.json
        store_packets( h_pkt, packets, options )
      else
        print_packets( packets, options )
      end

      cont = false if (options.count && num >= options.count)
      cont = false if (options.seconds && 
                       Time.now - h_pkt[:start_ts] >= options.seconds)

    rescue ConnectionTimeoutError, Interrupt => e
      cont = false
    end
  end

  if options.json
    puts packets_to_json( h_pkt, options )
  end
end

# ----------------------------------------------------------------------
def get_options(args)
  options = OpenStruct.new
  options.esense = false
  options.quality = false
  options.raw = false
  options.wave = false
  options.multi = false
  options.json = false
  options.verbose = false
  options.count = nil
  options.seconds = nil
  options.device = nil

  opts = OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename $0} [] [DEVICE]"
    opts.separator ""
    opts.separator "Options:"

      opts.on('-a', '--all', 'Capture all data types') { 
        options.esense = options.quality = options.raw = options.wave = true }
      opts.on('-e', '--esense', 'Capture eSense (attention, meditation) data') {
        options.esense = true }
      opts.on('q', '--quality', 'Capture signal quality data') { 
        options.quality = true }
      opts.on('-r', '--raw', 'Capture raw wave data') { options.raw = true }
      opts.on('-w', '--wave', 'Capture ASIC brainwave data') { 
        options.wave = true }
      opts.on('-j', '--json', 'Generate JSON output') { options.json = true }
      opts.on('-s', '--seconds n', 'Capture for n seconds') { |n| 
        options.seconds = Integer(n) }
      opts.on('-n', '--num n', 'Capture up to n data points') { |n| 
        options.count = Integer(n) }
      opts.on('-v', '--verbose', 'Show debug output') { options.verbose = true }
      opts.on_tail('-h', '--help', 'Show help screen') { puts opts; exit 1 }
    end

    opts.parse! args
    options.wave = true if (! options.wave) && (! options.esense) && 
                           (! options.raw) && (! options.quality)
    options.multi = [ options.wave, options.raw,  option.esense, 
                      options.quality ].select { |x| x }.count > 1
                   
    options.device = args.shift if args.length > 0

    options
end

if __FILE__ == $0
  read_bt_data(get_options ARGV)
end
