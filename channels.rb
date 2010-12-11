# Erie stuff

require 'eventmachine'
require 'state_machine'

module ResourceHandler
  def resources
    @resources ||= Resources.new
  end
  def start_inputs
    start_resources(resources.inputs)
  end
  def stop_inputs
    stop_resources(resources.inputs)
  end
  def start_outputs
    start_resources(resources.inputs)
  end
  def stop_outputs
    stop_resources(resources.inputs)
  end
  private
  def start_resources(r)
    r.each {|n,r| r.start}
  end
  def stop_resources(r)
    r.each {|n,r| r.stop}
  end  
end

class Application
  extend ResourceHandler
  def self.start_handlers
    start_resources(resources.handlers)
  end
  def self.stop_handlers
    stop_resources(resources.handlers)
  end
end

class Resources
  attr_reader :inputs, :outputs, :handlers
  def initialize
    @inputs = {}
    @outputs = {}
    @handlers = {}
  end
  def specify(&b)
    self.instance_exec(&b)
  end
  def input(name, input_resource, options={})
    puts 'name: ' + name.to_s + ' input_resource: ' + input_resource.inspect
    @inputs[name] = input_resource
  end
  def output(name, output_resource, options={})
    puts 'name: ' + name.to_s + ' output_resource: ' + output_resource.inspect
    @outputs[name] = output_resource
  end
  def handler(name, handler_resource, options={}, &b)
    puts 'name: ' + name.to_s + ' handler_resource: ' + handler_resource.inspect
    @handlers[name] = handler_resource
    handler_resource.resources.instance_exec(&b) if block_given?
  end
end

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
  include ResourceHandler
  state_machine {after_transition :on => :start, :do => [:start_inputs, :start_outputs]}
  state_machine {after_transition :on => :stop, :do => [:stop_outputs, :stop_inputs]}
  def handle;end
end

# application stuff
# inputs/random_input.rb
class RandomInput < InputResource
  def initialize(name,max_delay)
    @name = name
    @max_delay = max_delay
    super()
  end
  def setup
    puts 'activating random input ' + @name
  end
  def receive
    @timer = EventMachine::Timer.new(v=(rand * @max_delay)) do
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
    [
      [Application.resources.inputs.values, Application.resources.outputs.values],
      [self.resources.inputs.values, self.resources.outputs.values]
    ].each do |i,o|
      i.each do |i|
        o.each do |o|
          i.subscribe do |message|
            handle(o,message)
          end
        end
      end
    end
  end
  
  def handle(output,message)
    output.transmit message
  end
  
end

Application.resources.specify do
  handler :random, RandHandler.new
  
  input :first, RandomInput.new('first', 1.0)
  input :second, RandomInput.new('second', 1.0), :auto_start => false

  output :red, PutsOutput.new('red')
  output :blue, PutsOutput.new('blue')

  handler :tigers, RandHandler.new do
    input :pitch, RandomInput.new('pitch',3.0)
    output :home_run, PutsOutput.new('home_run')
  end

  handler :special_random, RandHandler.new do
    input :shiny, RandomInput.new('shiny',4.0)
    output :fireworks, PutsOutput.new('fireworks')
  end

end

class Server
  def self.start
    EM.run do
      Application.start_handlers
      Application.start_outputs
      Application.start_inputs
      EM.add_timer(10) do
        Application.stop_inputs
        Application.stop_outputs
        Application.stop_handlers
        EM.stop
      end
    end
  end
end
Server.start