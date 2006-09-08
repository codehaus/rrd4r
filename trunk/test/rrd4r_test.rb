
require 'rrd4r'
require 'pp'
require 'stringio'

require 'test/unit'

class RrdToolTest < Test::Unit::TestCase

  def test_create()
    #rrd = Rrd4r::Rrd.create( "/tmp/rrd4r-test-#{Process.pid}",
                             #:step=>22,
                             #:data_sources=>[ 
                               #Rrd4r::Rrd::Gauge.new(:gb_used, :heartbeat=>63 ) 
                             #],
                             #:archives=>[ 
                               #Rrd4r::Rrd::Average.new(:steps=>10, :rows=>20)
                             #] )

    rrd = Rrd4r::Rrd.create( "/tmp/rrd4r-test-#{Process.pid}",
                             :step=>22 ) do |builder|
                               builder.gauge :gb_used, :heartbeat=>63 
                               builder.average :steps=>10, :rows=>20 
                             end 
    pp rrd

    rrd.update( :gb_used=>10 )
    puts "last: #{rrd.last}"

    graph = Rrd4r::Graph.create( :title=>'Yeah, buddy',
                                 :defs=>[ 
                                   rrd[ :gb_used ].def( :gb_used, :average ) 
                                 ],
                                 :graphs=>[
                                   Rrd4r::Graph::Line.new( :gb_used, :width=>2, :color=>'#000099', :legend=>"GB Used" )
                                 ] )
    pp graph
    graph.to_png :outfile=>'/tmp/bob.png'
  end

end
