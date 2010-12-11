# Erie stuff

require 'eventmachine'
require 'state_machine'

module ResourcesHandler
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
  def start_handlers
    start_resources(resources.handlers)
  end
  def stop_handlers
    stop_resources(resources.handlers)
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
  extend ResourcesHandler
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
    raise "'#{name}' is not an #{InputResource.name}." unless input_resource.is_a?(InputResource)
    puts 'name: ' + name.to_s + ' input_resource: ' + input_resource.inspect
    @inputs[name] = input_resource
  end
  def output(name, output_resource, options={})
    raise "'#{name}' is not an #{OutputResource.name}." unless output_resource.is_a?(OutputResource)
    puts 'name: ' + name.to_s + ' output_resource: ' + output_resource.inspect
    @outputs[name] = output_resource
  end
  def handler(name, handler_resource, options={}, &b)
    raise "'#{name}' is not an #{ApplicationHandler.name}." unless handler_resource.is_a?(ApplicationHandler)
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
  state_machine {after_transition :on => :start, :do => :start_timer}
  state_machine {after_transition :on => :stop, :do => :stop_timer}
  def receive;end
  
  def initialize(options={})
    @channel = EM::Channel.new
    @name = options[:name]
    @frequency = options[:frequency] || 1.0
    raise "for input '#{@name}' frequency must be greater than 0.0" if @frequency <= 0.0
    super()
  end
  
  def start_timer
    @timer = EventMachine::Timer.new(1.0 / @frequency) do
      EM.defer {
        receive
      }
      start_timer
    end
  end
  
  def stop_timer
    @timer.cancel
  end
  
  def subscribe(*a, &b)
    @channel.subscribe(*a, &b)
  end
end

class OutputResource < Base
  def transmit;end
end

class ApplicationHandler < Base
  include ResourcesHandler
  state_machine {after_transition :on => :start, :do => [:start_handlers, :start_outputs, :start_inputs]}
  state_machine {after_transition :on => :stop, :do => [:stop_inputs, :stop_outputs, :stop_handlers]}
  def handle;end
end

# application stuff
# inputs/random_input.rb
class RandomInput < InputResource
  def setup
    puts 'activating random input ' + @name
  end
  def receive
    @channel << [@name, Time.now, rand]
  end
  def teardown
    puts 'deactivating random input ' + @name
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
  input :global, RandomInput.new(:name => 'global')
  output :global, PutsOutput.new('global')
  handler :global, RandHandler.new

  handler :slum_village, RandHandler.new do
    input :dilla, RandomInput.new(:name => 'dilla')
    output :black_milk, PutsOutput.new('hip_hop')
    handler :d12, RandHandler.new do
      input :shady, RandomInput.new(:name => 'shady')
      output :proof, PutsOutput.new('proof')
    end
  end

  handler :tigers, RandHandler.new do
    input :pitch, RandomInput.new(:name => 'pitch', :frequency => 0.5)
    output :home_run, PutsOutput.new('home_run')
  end

  handler :special_random, RandHandler.new do
    input :shiny, RandomInput.new(:name => 'shiny', :frequency => 0.25)
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