require 'eventmachine'
require 'state_machine'

class InputResource
  
  attr_reader :channel
  
  def initialize
    @channel = EM::Channel.new
    super()
  end
  
  state_machine :initial => :inactive do
    after_transition :on => :start, :do => [:activate, :receive]
    after_transition :on => :stop, :do => :deactivate
    
    event :start do
      transition :inactive => :active
    end
    event :stop do
      transition :active => :inactive
    end    
  end
end

class RandomInput < InputResource
  def initialize(name)
    @name = name
    super()
  end
  def activate
    puts 'activating random input ' + @name
  end
  def receive
    @timer = EventMachine::Timer.new(v=(rand * 1.0)) do
      EM.defer {
        # pushes data into channel
        @channel << [@name, Time.now, v]
      }
      receive
    end
  end
  def deactivate
    puts 'deactivating random input ' + @name
    @timer.cancel
  end
end

class OutputResource
end
class PutsOutput < OutputResource
  def initialize(name)
    @name = name
  end
  def transmit(data)
    puts @name + ': ' + data.inspect
  end
end

class ApplicationHandler
end
class RandHandler < ApplicationHandler
  
  def initialize(options)
    @inputs = options[:inputs]
    @outputs = options[:outputs]
  end
  
  def activate
    @inputs.each do |i|
      @outputs.each do |o|
        i.channel.subscribe do |message|
          handle(o,message)
        end
      end
    end
    @inputs.each { |i| i.start }
  end
  
  def handle(output,message)
    output.transmit message
  end
  
  def deactivate
    @inputs.each { |i| i.stop }
  end
  
end
EM.run do
  random_input_one = RandomInput.new('one')
  random_input_two = RandomInput.new('two')
  
  puts_output_red = PutsOutput.new('red')
  puts_output_blue = PutsOutput.new('blue')

  h = RandHandler.new :inputs => [random_input_one, random_input_two], :outputs => [puts_output_red, puts_output_blue]
  h.activate
  
  EM.add_timer(10) do
    h.deactivate
    EM.stop
  end
end
