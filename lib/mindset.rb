#!/usr/bin/env ruby
# :title: Mindset
# Ruby module for reading data from a Neurosky Mindset.
# (c) Copyright 2014 mkfs@github http://github.com/mkfs/mindset                 
# License: BSD http://www.freebsd.org/copyright/freebsd-license.html

=begin rdoc
DRb service which manages a Neurosky Mindset headset. Only one headset can
be associated with a single DRb service.

Example:

server = Mindset::Device.start
server.connect('/dev/rfcomm1')

# ... read data here ...

server.disconnect()
server.stop
=end
module Mindset
  autoload :Connection, 'mindset/connection.rb'
  autoload :Device, 'mindset/device.rb'
  autoload :LoopbackConnection, 'mindset/connection.rb'
  autoload :Packet, 'mindset/packet.rb'
  autoload :PacketStore, 'mindset/packet.rb'
end
