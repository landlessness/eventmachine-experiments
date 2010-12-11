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
    def input(name, input_resource_clazz, options={})
      input_resource = input_resource_clazz.new options
      raise "'#{name}' is not an #{InputResource.name}." unless input_resource.is_a?(InputResource)
      input_resource.name = name.to_s
      @inputs[name] = input_resource
    end
    def output(name, output_resource_clazz, options={})
      output_resource = output_resource_clazz.new options
      raise "'#{name}' is not an #{OutputResource.name}." unless output_resource.is_a?(OutputResource)
      output_resource.name = name.to_s
      @outputs[name] = output_resource
    end
    def handler(name, handler_resource_clazz, options={}, &b)
      handler_resource = handler_resource_clazz.new options
      raise "'#{name}' is not an #{ApplicationHandler.name}." unless handler_resource.is_a?(ApplicationHandler)
      handler_resource.name = name.to_s
      @handlers[name] = handler_resource
      handler_resource.resources.instance_exec(&b) if block_given?
    end
  end

  class Base
    def initialize(options={})
      @name = options[:name]
      super
    end
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

    def subscribe(*a, &b)
      @channel.subscribe(*a, &b)
    end

    def initialize(options={})
      @channel = EM::Channel.new
      @frequency = options[:frequency] || 1.0
      raise "for input '#{@name}' frequency must be greater than 0.0" if @frequency <= 0.0
      super(options)
    end

    protected

    state_machine {after_transition :on => :start, :do => :start_timer}
    state_machine {after_transition :on => :stop, :do => :stop_timer}

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

    attr_reader :channel
    def receive;end

  end

  class OutputResource < Base
    protected
    def transmit;end
  end

  class ApplicationHandler < Base
    # TODO: make this a singleton
    include ResourcesHandler
    state_machine {after_transition :on => :start, :do => [:setup_hooks, :start_handlers, :start_outputs, :start_inputs]}
    state_machine {after_transition :on => :stop, :do => [:stop_inputs, :stop_outputs, :stop_handlers]}

    def handle;end

    def self.create_attr_reader(name)
      protected
      attr_reader name
    end

    def setup_hooks
      self.resources.inputs.each do |k,v|
        ApplicationHandler.create_attr_reader("#{k}_value")
        ApplicationHandler.create_attr_reader("#{k}_input")
        instance_variable_set("@#{k}_input",v)
        instance_variable_set("@#{k}_value",0.0)
        v.subscribe do |d|
          instance_variable_set("@#{k}_value",d)
          instance_eval("#{k}_updated")
        end
      end

      self.resources.outputs.each do |k,v|
        ApplicationHandler.create_attr_reader("#{k}_output")
        instance_variable_set("@#{k}_output",v)
      end

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

end

# application stuff
# inputs/random_input.rb
class RandomInput < Erie::InputResource
  def receive
    channel << rand
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

  def transmit
    puts name + ': ' + self.light_state
  end

end

# handlers/rand_handlers.rb
class RandHandler < Erie::ApplicationHandler
  def sound_updated
    toggle_blue_led
  end

  def light_updated
    toggle_blue_led
  end

  def proximity_updated
    if proximity_value > 0.5
      red_led_output.turn_on
      green_led_output.turn_off
    else
      red_led_output.turn_off
      green_led_output.turn_on
    end
  end

  def toggle_blue_led
    light_value > 0.5 && sound_value > 0.5 ? blue_led_output.turn_on : blue_led_output.turn_off
  end

end

Erie::Application.resources.specify do
  handler :leds, RandHandler do
    input :light, RandomInput, frequency: 3.0
    input :proximity, RandomInput, frequency: 2.0
    input :sound, RandomInput
    
    output :red_led, FauxLEDOutput
    output :green_led, FauxLEDOutput, pin: 13
    output :blue_led, FauxLEDOutput, pin: 14
  end
end

Erie::Server.start