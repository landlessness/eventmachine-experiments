module Erie
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
      start_resources(resources.outputs)
    end
    def stop_outputs
      stop_resources(resources.outputs)
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
      input_resource.name = name.to_s
      @inputs[name] = input_resource
    end
    def output(name, output_resource, options={})
      raise "'#{name}' is not an #{OutputResource.name}." unless output_resource.is_a?(OutputResource)
      puts 'name: ' + name.to_s + ' output_resource: ' + output_resource.inspect
      output_resource.name = name.to_s
      @outputs[name] = output_resource
    end
    def handler(name, handler_resource, options={}, &b)
      raise "'#{name}' is not an #{ApplicationHandler.name}." unless handler_resource.is_a?(ApplicationHandler)
      puts 'name: ' + name.to_s + ' handler_resource: ' + handler_resource.inspect
      handler_resource.name = name.to_s
      @handlers[name] = handler_resource
      handler_resource.resources.instance_exec(&b) if block_given?
    end
  end

  class Base
    attr_accessor :name
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
          receive if self.active?
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
    # TODO: make this a singleton
    include ResourcesHandler
    state_machine {after_transition :on => :start, :do => [:start_handlers, :start_outputs, :start_inputs]}
    state_machine {after_transition :on => :stop, :do => [:stop_inputs, :stop_outputs, :stop_handlers]}
    def handle;end
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

end

# application stuff
# inputs/random_input.rb
class RandomInput < Erie::InputResource
  def setup
    puts 'setup random input ' + @name
  end
  def receive
    @channel << rand
  end
  def teardown
    puts 'teardown random input ' + @name
  end
end

# outputs/puts_output.rb
class FauxLEDOutput < Erie::OutputResource
  state_machine :light_state, :initial => :dark do
    event :turn_on do
      transition :dark => :light
    end
    event :turn_off do
      transition :light => :dark
    end
    after_transition :do => :transmit
  end
  
  def setup
    puts 'setup puts output ' + @name
  end
  def transmit
    puts @name + ': ' + self.light_state
  end
  def teardown
    puts 'teardown puts output ' + @name
  end
end

# handlers/rand_handlers.rb
class RandHandler < Erie::ApplicationHandler
  def setup
    puts 'setup rand handler ' + @name

    # do this stuff below automatically in the base class?
    # set the _input, _value and _update
    # auto-subscribe to the input channels
    # set an object variable with the current value
    # then call a callback
    @proximity_value = @sound_value = @light_value = 0.0

    @light_input = self.resources.inputs[:light]
    @proximity_input = self.resources.inputs[:proximity]
    @sound_input = self.resources.inputs[:sound]

    @red_led_output = self.resources.outputs[:red_led]
    @green_led_output = self.resources.outputs[:green_led]
    @blue_led_output = self.resources.outputs[:blue_led]

    @proximity_input.subscribe do |d|
      @promixity_value = d
      proximity_update
    end
    
    @sound_input.subscribe do |d|
      @sound_value = d
      sound_update
    end
    
    @light_input.subscribe do |d|
      @light_value = d
      light_update
    end

  end

  def sound_update
    toggle_blue_led
  end

  def light_update
    toggle_blue_led
  end

  def proximity_update
    if @promixity_value > 0.5
      @red_led_output.turn_on
      @green_led_output.turn_off
    else
      @red_led_output.turn_off
      @green_led_output.turn_on
    end
  end

  def toggle_blue_led
    @light_value > 0.5 && @sound_value > 0.5 ? @blue_led_output.turn_on : @blue_led_output.turn_off
  end

  def teardown
    puts 'teardown rand handler ' + @name
  end

end

Erie::Application.resources.specify do
  handler :leds, RandHandler.new do
    input :light, RandomInput.new
    input :proximity, RandomInput.new
    input :sound, RandomInput.new
    
    output :red_led, FauxLEDOutput.new
    output :green_led, FauxLEDOutput.new
    output :blue_led, FauxLEDOutput.new
  end
end

Erie::Server.start