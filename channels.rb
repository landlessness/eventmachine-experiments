require 'eventmachine'
require 'state_machine'

class InputResource < EM::Channel
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
end

class RandomInput < InputResource
  def activate
    puts 'activating random input'
    gather_input
  end
  def gather_input(v=0)
    @timer = EventMachine::Timer.new(v=(rand * 2)) do
      EM.defer lambda {self << [Time.now, v] }
      EventMachine::Timer.new(v=(rand * 2)) {gather_input(v)}
    end
  end
  def deactivate
    puts 'deactivating random input'
    @timer.cancel
  end
end

EM.run do
  random_input = RandomInput.new

  random_input.subscribe do |m|
    puts '1: ' + m.inspect
  end

  random_input.subscribe do |m|
    puts '2: ' + m.inspect
  end

  random_input.start

  EM.add_timer(60) do
    EM.stop
    random_input.stop
  end
end