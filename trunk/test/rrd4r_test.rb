
require 'rrd4r'
require 'pp'
require 'stringio'

require 'test/unit'

class RrdToolTest < Test::Unit::TestCase

  def test_create()
    rrd = Rrd4r::Rrd.create( "/tmp/rrd4r-test-#{Process.pid}",
                             :step=>22,
                             :data_sources=>[ 
                               Rrd4r::Rrd::Gauge.new(:gb_used, :heartbeat=>63 ) 
                             ],
                             :archives=>[ 
                               Rrd4r::Rrd::Average.new(:steps=>10, :rows=>20)
                             ] )
    #pp rrd
    rrd.update( :gb_used=>10 )
    puts "last: #{rrd.last}"

    graph = Rrd4r::Graph.create( :defs=>{ 
                                   :average => rrd[ :gb_used ].graph_def( :average ) 
                                 } )
    pp graph
  end

end
