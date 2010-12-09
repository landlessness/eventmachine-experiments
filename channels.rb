require 'eventmachine'
require 'state_machine'

class InputResource < EM::Channel
  state_machine :initial => :inactive do
    after_transition :on => :start, :do => [:activate, :gather]
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
  def activate
    puts 'activating random input'
  end
  def gather
    @timer = EventMachine::Timer.new(v=(rand * 1.0)) do
      EM.defer lambda {self << [Time.now, v] }
      gather
    end
  end
  def deactivate
    puts 'deactivating random input'
    @timer.cancel
  end
end

EM.run do
  random_input_1 = RandomInput.new
  random_input_2 = RandomInput.new

  random_input_1.subscribe do |m|
    puts 'input 1 output 1: ' + m.inspect
  end

  random_input_1.subscribe do |m|
    puts 'input 1 output 2: ' + m.inspect
  end

  random_input_2.subscribe do |m|
    puts 'input 2 output 1: ' + m.inspect
  end

  random_input_2.subscribe do |m|
    puts 'input 2 output 2: ' + m.inspect
  end

  random_input_1.start
  random_input_2.start

  EM.add_timer(10) do
    random_input_1.stop
    random_input_2.stop
    EM.stop
  end
end
