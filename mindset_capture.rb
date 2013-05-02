#!/usr/bin/env ruby
# Receive data from bluetooth and print to stdout. Assumes /dev/rfcomm0.
# Usage: 
#   mindset_capture.rb [-aehjqrvw] [-sn num] [DEVICE]
# (c) Copyright 2013 mkgs@github http://github.com/mkfs/mindset                 
# License: BSD http://www.freebsd.org/copyright/freebsd-license.html

require 'ostruct'
require 'optparse'

require 'mindset'

# ----------------------------------------------------------------------
# Treat 3-element array as a 3-byte integer in big-endian order
# Note: This zero-pads the integer to 4-bytes before calling unpack, which
#       may not be correct if the values can be signed.
=begin
  def unpack_3byte_bigendian(arr)
    arr.unshift(0).pack('cccc').unpack('L>').first
  end

  def unpack_asic_eeg(arr)
    { :delta => unpack_3byte_bigendian(arr[0,3]),
      :theta => unpack_3byte_bigendian(arr[3,3]),
      :lo_alpha => unpack_3byte_bigendian(arr[6,3]),
      :hi_alpha => unpack_3byte_bigendian(arr[9,3]),
      :lo_beta => unpack_3byte_bigendian(arr[12,3]),
      :hi_beta => unpack_3byte_bigendian(arr[15,3]),
      :lo_gamma => unpack_3byte_bigendian(arr[18,3]),
      :mid_gamma => unpack_3byte_bigendian(arr[21,3])
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
      { :wave => value[0,2].join('').unpack("s>").first }
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

  def is_asic_wave?(pkt)
    ([:lo_beta, :hi_beta, :delta, :lo_gamma, :theta, :mid_gamma, :lo_alpha, 
      :hi_alpha] & pkt.keys).count > 0
  end

  def is_esense?(pkt)
    (pkt.keys.include? :attention) || (pkt.keys.include? :meditation)
  end

  def skip_packet?(pkt, options)
    ((pkt.keys.include? :wave) && ! options.raw) ||
    ((pkt.keys.include? :signal_quality) && ! options.quality) ||
    ((is_asic_wave? pkt) && ! options.wave) ||
    ((is_esense? pkt) && ! options.esense)
  end

  def store_packets( h, packets, options )
    packets.each { |pkt| pkt.each { |k,v| h[k] << v } }
  end

  def print_packets( packets, options )
    label = options.multi || options.verbose
    packets.each do |pkt|
      pkt.each { |k,v| puts "%s%d" % [(label ? k.to_s.upcase + ': ' : ''), v] }
    end
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
=end

# ----------------------------------------------------------------------
def skip_packet?(pkt, options)
  ((pkt.keys.include? :wave) && ! options.raw) ||
  ((pkt.keys.include? :signal_quality) && ! options.quality) ||
  ((is_asic_wave? pkt) && ! options.wave) ||
  ((is_esense? pkt) && ! options.esense)
end

def print_packets( packets, options )
  label = options.multi || options.verbose
  packets.each do |pkt|
    pkt.each { |k,v| puts "%s%d" % [(label ? k.to_s.upcase + ': ' : ''), v] }
  end
end

def read_mindset_bt(options)
  conn = Mindset.connect(options.device, options.verbose)
  return if ! conn

  h_pkt = Mindset::PacketStore.new
  num = 0
  cont = true
  while cont
    begin
      packets = conn.read_packet(options.verbose).reject { |pkt| 
                skip_packet? pkt, options }
      num += packets.length
      if options.json
        store_packets( h_pkt, packets, options )
      else
        print_packets( packets, options )
      end

      cont = false if (options.count && num >= options.count)
      cont = false if (options.seconds && 
                       Time.now - h_pkt[:start_ts] >= options.seconds)

      rescue Mindset::Connection::TimeoutError, Interrupt => e
        cont = false
    end
  end

  conn.disconnect

  if options.json
    h_pkt[:end_ts] = Time.now
    puts packets_to_json( h_pkt, options )
  end
end

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
  options.device = DEFAULT_SERIAL_PORT

  opts = OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename $0} [-aehjqrvw] [-sn num] [DEVICE]"
    opts.separator ""
    opts.separator "Notes:"
    opts.separator " * DEVICE defaults to /dev/rfcomm0"
    opts.separator " * Ctrl-C will terminate if both -s and -n are not set"
    opts.separator " * JSON output will only be written on exit."
    opts.separator ""
     
    opts.separator "Options:"

      opts.on('-a', '--all', 'Capture all data types') { 
        options.esense = options.quality = options.raw = options.wave = true }
      opts.on('-e', '--esense', 'Capture eSense (attention, meditation) data') {
        options.esense = true }
      opts.on('-q', '--quality', 'Capture signal quality data') { 
        options.quality = true }
      opts.on('-r', '--raw', 'Capture raw wave data') { options.raw = true }
      opts.on('-w', '--wave', 'Capture ASIC brainwave data [default]') { 
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
    options.multi = [ options.wave, options.raw,  options.esense, 
                      options.quality ].select { |x| x }.count > 1
                   
    options.device = args.shift if args.length > 0

    options
end

if __FILE__ == $0
  read_mindset_bt(get_options ARGV)
end
