require 'eventmachine'
require 'state_machine'

class Base
  state_machine :initial => :inactive do
    after_transition :on => :start, :do => :activate
    after_transition :on => :stop, :do => :deactivate
    event :start do
      transition :inactive => :active
    end
    event :stop do
      transition :active => :inactive
    end    
  end
  def activate;end
  def deactivate;end
end

class InputResource < Base
  state_machine {after_transition :on => :start, :do => :receive}
  def receive;end
  
  def initialize
    @channel = EM::Channel.new
    super()
  end
  
  def subscribe(*a, &b)
    @channel.subscribe(*a, &b)
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

class OutputResource < Base
  def transmit;end
end

class PutsOutput < OutputResource
  def initialize(name)
    @name = name
    super()
  end
  def transmit(data)
    puts @name + ': ' + data.inspect
  end
end

class ApplicationHandler < Base
  def handle;end  
end
class RandHandler < ApplicationHandler
  
  def initialize(options)
    @inputs = options[:inputs]
    @outputs = options[:outputs]
    super()
  end
  
  def activate
    @inputs.each do |i|
      @outputs.each do |o|
        i.subscribe do |message|
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
  h.start
  
  EM.add_timer(10) do
    h.stop
    EM.stop
  end
end
