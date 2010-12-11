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
  
  def setup
    Application.resources.inputs.each do |n,i|
      Application.resources.outputs.each do |k,o|
        i.subscribe do |message|
          handle(o,message)
        end
      end
    end
  end
  
  def handle(output,message)
    output.transmit message
  end
  
end

class ApplicationResources
  attr_reader :inputs, :outputs, :handlers
  def initialize
    @inputs = {}
    @outputs = {}
    @handlers = {}
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
  def handler(name, handler_resource)
    puts 'name: ' + name.to_s + ' handler_resource: ' + handler_resource.inspect
    @handlers[name] = handler_resource
  end
end

class Application
  def self.resources
    @@resources ||= ApplicationResources.new
  end
  def self.start_inputs
    start_resources(@@resources.inputs)
  end
  def self.stop_inputs
    stop_resources(@@resources.inputs)
  end
  def self.start_outputs
    start_resources(@@resources.inputs)
  end
  def self.stop_outputs
    stop_resources(@@resources.inputs)
  end
  def self.start_handlers
    start_resources(@@resources.handlers)
  end
  def self.stop_handlers
    stop_resources(@@resources.handlers)
  end
  private
  def self.start_resources(r)
    r.each {|n,r| r.start}
  end
  def self.stop_resources(r)
    r.each {|n,r| r.stop}
  end
end

Application.resources.specify do
  handler :random, RandHandler.new
  
  input :first, RandomInput.new('first')
  input :second, RandomInput.new('second')
  
  output :red, PutsOutput.new('red')
  output :blue, PutsOutput.new('blue')
end

EM.run do
  Application.start_handlers
  Application.start_outputs
  Application.start_inputs
  EM.add_timer(10) do
    Application.stop_handlers
    Application.stop_outputs
    Application.stop_inputs
    EM.stop
  end
end
