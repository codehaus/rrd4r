
module Rrd4r

  DEBUG = true
  RRDTOOL_BIN = `which rrdtool`.chomp

  class Rrd

    class DataSource
      def initialize(name)
        @name = name.to_sym
      end
      def name
        @name
      end
      def rrd
        @rrd
      end
      def rrd=(rrd)
        @rrd = rrd
      end
      def update(value)
        update_at( :N, value )
      end
      def update_at(timestamp, value)
        @rrd.update_at( timestamp, { @name=>value } )
      end
      def def(vname, cf, options={})
        Rrd4r::Graph::Def.new( vname, self, cf, options )
      end
    end

    class NormalDataSource < DataSource
      def initialize(name, type, options={})
        super( name )
        @type = type
        @heartbeat = options[:heartbeat]
        @min       = options[:min] || 'U'
        @max       = options[:max] || 'U'
      end
      def to_s
        s = "DS:#{name}:#{@type.to_s.upcase}:#{@heartbeat}:#{@min}:#{@max}"
      end
    end

    class Gauge < NormalDataSource
      def initialize(name, options={})
        super( name, :gauge, options )
      end
    end

    class Counter < NormalDataSource
      def initialize(name, options={})
        super( name, :counter, options )
      end
    end

    class Derive < NormalDataSource
      def initialize(name, options={})
        super( name, :derive, options )
      end
    end

    class Absolute < NormalDataSource
      def initialize(name, options={})
        super( name, :absolute, options )
      end
    end

    class Compute < DataSource
      def initialize(name, rpn_expression)
        super( name )
        @rpn_expression = rpn_expression
      end
      def to_s
        "DS:#{name}:COMPUTE:#{@rpn_expression}"
      end
    end

    class Archive
      def initialize(type,options={})
        @type  = type
        @xff   = options[:xff] || 0.5
        @steps = options[:steps] 
        @rows  = options[:rows] 
      end
      def to_s
        "RRA:#{@type.to_s.upcase}:#{@xff}:#{@steps}:#{@rows}"
      end
    end

    class Average < Archive
      def initialize(options={})
        super( :average, options )
      end 
    end

    class Min < Archive
      def initialize(options={})
        super( :min, options )
      end 
    end

    class Max < Archive
      def initialize(options={})
        super( :max, options )
      end 
    end

    class Last < Archive
      def initialize(options={})
        super( :last, options )
      end 
    end

    class Builder
      def initialize()
        @data_sources = []
        @archives = []
        if ( block_given? )
          yield( self )
        end
      end

      def data_sources
        @data_sources
      end

      def archives
        @archives
      end

      def gauge(name,options)
        @data_sources << Gauge.new( name, options )
      end

      def counter(name,options)
        @data_sources << Counter.new( name, options )
      end

      def derive(name,options)
        @data_sources << Derive.new( name, options )
      end

      def absolute(name,options)
        @data_sources << Absolute.new( name, options )
      end

      def compute(name,rpn_expression)
        @data_sources << Compute.new( name, rpn_expression )
      end

      def average(options)
        @archives << Average.new( options )
      end

      def min(options)
        @archives << Min.new( options )
      end

      def max(options)
        @archives << Max.new( options )
      end

      def last(options)
        @archives << Last.new( options )
      end

    end

    def self.create(rrd_path, options={}, &block)
      builder = Builder.new( &block )
      data_sources = ( options[:data_sources] || [] ) + builder.data_sources
      archives = ( options[:archives] || [] ) + builder.archives
      args = [ rrd_path ]
      if ( options[:start] )
        args << '--start'
        args << options[:start]
      end
      if ( options[:step] )
        args << '--step'
        args << options[:step]
      end
      if ( data_sources == nil or data_sources.empty? )
        raise RuntimeError.new( "at least 1 data-source must be supplied" )
      end
      for data_source in data_sources
        args << data_source.to_s
      end
      if ( archives == nil or archives.empty? )
        raise RuntimeError.new( "at least 1 archive must be supplied" )
      end
      for archive in archives
        args << archive.to_s
      end
      rrd_exec( :create, args ) 
      self.open( rrd_path )
    end

    def self.open(rrd_path)
      Rrd.new( rrd_path )
    end

    def initialize(rrd_path)
      @rrd_path = rrd_path
      @step     = nil
      @ds_ordered  = []
      @ds_by_name  = {}
      @rra_ordered = []
      connect_to_rrdtool()
      load_rrd_info()
    end

    def close()
      @rrd.close and @rrd = nil if @rrd
    end

    def [](name)
      @ds_by_name[name.to_sym]
    end

    def update(data={})
      update_at( :N, data )
    end

    def last()
      rrd_pipe( :last, @rrd_path ) do |result|
        Time.at( result.to_i )
      end
    end

    def update_at(timestamp, data={})
      if ( timestamp == :N )
        ts = 'N'
      else
        ts = timestamp.to_i
      end
      ds_names = data.keys
      template = "--template #{ds_names.join(':')}"
      values = data.values_at( *ds_names ).join(':')
      rrd_pipe( :update, @rrd_path, template, "#{ts}:#{values}" )
    end

    def rrd_path
      @rrd_path
    end

    private

    def connect_to_rrdtool()
      @rrd = open( "| #{Rrd4r::RRDTOOL_BIN} -", 'r+' ) 
    end

    def load_rrd_info()
      rrd_pipe( :info, @rrd_path ) do |output|
        current_ds  = { :name=>nil }
        current_rra = { :name=>nil }
        output.each_line do |line|
          case( line )
            when /^step = ([0-9]+)$/
              @step = $1.to_i
            when /^ds\[([A-Za-z0-9_]+)\]\.([a-z_]+) = (.*)$/
              if ( $1 != current_ds[:name] )
                _add_ds( current_ds )
                current_ds = { :name=>$1 }
              end
              current_ds[$2.to_sym]=$3
            when /^rra\[([A-Za-z0-9_]+)\]\.([a-z_]+) = (.*)$/
              if ( $1 != current_rra[:name] )
                _add_rra( current_rra )
                current_rra = { :name=>$1 }
              end
              current_rra[$2.to_sym]=$3
            #else
              #puts "****** UNHANDLED #{line}"
          end
        end
        _add_ds( current_ds )
        _add_rra( current_rra )
      end
    end

    def _add_ds(ds_data)
      return unless ds_data[:name]
      type_name = ds_data[:type].gsub( /"/, '' ).downcase.capitalize
      type = eval type_name
      ds = type.new( ds_data[:name],
                     :heartbeat=>ds_data[:minimal_heartbeat],
                     :min=>ds_data[:min],
                     :max=>ds_data[:max] )
      ds.rrd = self
      @ds_ordered << ds 
      @ds_by_name[ds.name] = ds
    end

    def _add_rra(rra_data)
      return unless rra_data[:name]
      type_name = rra_data[:cf].gsub( /"/, '' ).downcase.capitalize
      type = eval type_name
      rra = type.new( :steps=>rra_data[:pdp_per_row].to_i,
                      :rows=>rra_data[:rows].to_i,
                      :xff=>rra_data[:xff].to_f )
      @rra_ordered << rra
    end

    def rrd_pipe(command,*args)
      command_line = "#{command} #{args.flatten.join(' ')}"
      puts "DEBUG: Rrd4r: pipe: #{command_line}" if Rrd4r::DEBUG
      @rrd.puts( command_line )
      buffer = StringIO.new( '', 'r+' )
      error = nil
      while ( true ) 
        line = @rrd.gets
        puts "DEBUG: Rrd4r: #{line}" if Rrd4r::DEBUG
        if ( line =~ /^OK/ )
          break
        elsif ( line =~ /^ERROR:/ )
          error = line
          break
        else
          buffer.puts( line )
        end
      end
      buffer.close_write
      if ( error )
        puts error
      end
      result = buffer.string
      if ( ! error && block_given? )
        result = yield( buffer.string )
      end
      buffer.close
      result
    end

    def self.rrd_exec(command,*args)
      command_line = "#{Rrd4r::RRDTOOL_BIN} #{command} #{args.flatten.join(' ')}"
      puts "DEBUG: Rrd4r: exec: #{command_line}" if Rrd4r::DEBUG
      Kernel.open( '| ' + command_line, 'r' ) do |io|
        io.each_line do |line|
          puts "DEBUG: Rrd4r: #{line}" if Rrd4r::DEBUG
        end
      end 
    end

  end

  class Graph
    class Def
      def initialize(vname, data_source, cf, options={})
        @vname = vname
        @data_source = data_source
        @cf          = cf.to_s.upcase.to_sym
        @step   = options[:step]
        @start  = options[:start]
        @end    = options[:end]
        @reduce = options[:reduce]
      end
      def to_s
        s = "DEF:#{@vname}=#{@data_source.rrd.rrd_path}:#{@data_source.name}:#{@cf}"
        s += ":step=#{@step}"     if ( @step )
        s += ":start=#{@start}"   if ( @start )
        s += ":end=#{@end}"       if ( @end )
        s += ":reduce=#{@reduce}" if ( @reduce )
        s
      end
    end

    class Vdef
      def initialize(vname,rpn_expression)
        @vname = vname
        @rpn_expression = rpn_expression
      end
    end

    class Cdef
      def initialize(vname,rpn_expression)
        @vname = vname
        @rpn_expression = rpn_expression
      end
    end

    class GraphElement
    end

    class Line
      def initialize(value,options={})
        @value  = value
        @width  = options[:width] || '' 
        if ( options[:color] )
          case ( options[:color] )
            when String
              @color = options[:color]
            when Integer
              @color = sprintf( '%08x', options[:color] )
          end
        end
        @legend = options[:legend] || value.to_s
        @stack  = options[:stack]
      end
      def to_s
        s = "LINE#{@width}:#{@value}"
        s += "#{@color}"     if ( @color )
        s += ":'#{@legend}'"
        s += ':STACK'        if ( @stack )
        s
      end
    end

    class Area
      def initialize(value,options={})
        @value  = value
        @color  = options[:color]
        @legend = options[:legend] || value.to_s
        @stack  = options[:stack]
      end
      def to_s
        s = "AREA:#{@value}"
        s += "#{@color}"     if ( @color )
        s += ":'#{@legend}'"
        s += ':STACK'        if ( @stack )
        s
      end
    end

    class Builder
      def initialize()
        @defs = []
        @graphs = []
        if ( block_given? )
          yield( self )
        end
      end
      def defs
        @defs
      end
      def graphs
        @graphs
      end
      def def(vname, data_source, cf, options={})
        @defs << Def.new( vname, data_source, cf, options )
      end
      def line(value,options={})
        @graphs << Line.new( value, options )
      end
      def area(value,options={})
        @graphs << Area.new( value, options )
      end
    end

    def self.create(options={},&block)
      builder = Builder.new( &block )
      options[:defs]   = ( options[:defs] || [] ) + builder.defs
      options[:graphs] = ( options[:graphs] || [] ) + builder.graphs
      graph = Graph.new( options )
    end

    def initialize(options)
      @title          = options[:title]
      @vertical_label = options[:vertical_label]
      @defs   = options[:defs] 
      @vdefs  = options[:vdefs] 
      @cdefs  = options[:cdefs] 
      @graphs = options[:graphs]
    end

    def to_png(options={})
      to_image( :png, options )
    end

    def to_image(type,options={})
      outfile = options[:outfile] || '-'
      args = [ "--imgformat #{type.to_s.upcase}" ]
      args << "--title '#{@title}'" if @title
      args << "--width #{options[:width]}"   if options[:width]
      args << "--height #{options[:height]}" if options[:height]
      args << "--start #{options[:start]}" if options[:start]
      args << "--end #{options[:end]}" if options[:end]
      args << "--lower-limit #{options[:lower_limit]}" if options[:lower_limit]

      if ( options[:color] )
        options[:color].each do |key,value|
          args << "--color #{key.to_s.upcase}#{value}"
        end
      end

      for d in @defs
        args << d.to_s
      end
      for g in @graphs
        args << g.to_s
      end

      command_line = "#{Rrd4r::RRDTOOL_BIN} graph #{outfile} #{args.flatten.join(' ')}"
      puts "DEBUG: Rrd4r: exec: #{command_line}" if Rrd4r::DEBUG
      image_data = nil
      open( '| ' + command_line ) do |io|
        image_data = io.read( ) if ! options[:outfile]
      end    
      image_data
    end
  end

end
