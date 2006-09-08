
require 'rrd4r'
require 'pp'
require 'stringio'

require 'test/unit'

class RrdToolTest < Test::Unit::TestCase

  def test_create()

    rrd = Rrd4r::Rrd.create( "/tmp/rrd4r-test-#{Process.pid}",
                             :step=>22 ) do |builder|
                               builder.gauge :gb_used, :heartbeat=>63 
                               builder.average :steps=>10, :rows=>20 
                             end 

    rrd.update( :gb_used=>10 )
    rrd.close

    graph = Rrd4r::Graph.create( :title=>'Yeah, buddy' ) do |builder|
                                   builder.def( :gb_used, rrd[:gb_used], :average)
                                   builder.line( :gb_used )
                                 end

    graph.to_png :outfile=>'/tmp/bob.png', :width=>800, :height=>10
  end

end
