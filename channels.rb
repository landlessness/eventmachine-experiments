# Erie stuff

require 'eventmachine'
require 'state_machine'

class Base
  state_machine :initial => :inactive do
    after_transition :on => :start, :do => :setup
    after_transition :on => :stop, :do => :teardown
    event :start do
      transition :inactive => :active
    end
    event :stop do
      transition :active => :inactive
    end    
  end
  def setup;end
  def teardown;end
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

class OutputResource < Base
  def transmit;end
end

class ApplicationHandler < Base
  def handle;end  
end

# application stuff
# inputs/random_input.rb
class RandomInput < InputResource
  def initialize(name)
    @name = name
    super()
  end
  def setup
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
  def teardown
    puts 'deactivating random input ' + @name
    @timer.cancel
  end
end
# outputs/puts_output.rb
class PutsOutput < OutputResource
  def initialize(name)
    @name = name
    super()
  end
  def transmit(data)
    puts @name + ': ' + data.inspect
  end
end
# handlers/rand_handlers.rb
class RandHandler < ApplicationHandler
  
  def initialize(options)
    @inputs = options[:inputs]
    @outputs = options[:outputs]
    super()
  end
  
  def setup
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
  
  def teardown
    @inputs.each { |i| i.stop }
  end
  
end

class ApplicationResources
  def initialize
    @inputs = @outputs = {}
  end
  def specify(&b)
    self.instance_exec(&b)
  end
  def input(name,input_resource)
    puts 'name: ' + name.to_s + ' input_resource: ' + input_resource.inspect
    @inputs[name] = input_resource
  end
  def output(name, output_resource)
    puts 'name: ' + name.to_s + ' output_resource: ' + output_resource.inspect
    @outputs[name] = output_resource
  end
end

class Application
  def self.resources
    @@resources ||= ApplicationResources.new
  end
end

Application.resources.specify do
  input :first, RandomInput.new('first')
  input :second, RandomInput.new('second')
  output :red, PutsOutput.new('red')
  output :blue, PutsOutput.new('blue')
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
