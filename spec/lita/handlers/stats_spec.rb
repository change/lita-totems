require "spec_helper"
require 'signalfx'

describe 'Stats' do

 totem = "dummy_totem4"

 describe 'capture_totem_use' do
   it 'sends totems:add:#{totem} metric and 1 as a value to signalfx counters' do
     expect(Stats).to receive(:send_counter_to_signalFX).with("totems:add:#{totem}", 1)
     Stats.capture_totem_use(totem)
   end

   it 'recieves the specified totem' do
     expect(Stats).to receive(:capture_totem_use).with(totem).and_call_original
     Stats.capture_totem_use(totem)
   end
  end

 describe 'capture_people_waiting' do
   it 'sends totems:people_waiting:#{totem} metric and the queue size as a value to signalfx gauges' do
     queue_size = "2"
     expect(Stats).to receive(:send_gauges_to_signalFX).with("totems:people_waiting:#{totem}", "2")
     Stats.capture_people_waiting(totem, queue_size)
   end

   it 'recieves the specified totem and the waiting peoples queue size' do
     queue_size = "2"
     expect(Stats).to receive(:capture_people_waiting).with(totem, queue_size).and_call_original
     Stats.capture_people_waiting(totem, queue_size)
   end
  end

  describe 'capture_holding_time' do
   it 'sends totems:holding_time:#{totem} metric and the holding time in minutes as a value to signalfx gauges' do
    Timecop.freeze("2014-03-01 13:00:00") do
     waiting_since_hash_user_id = "1393675200"
     expect(Stats).to receive(:send_gauges_to_signalFX).with("totems:holding_time:#{totem}", 60)
     Stats.capture_holding_time(totem, waiting_since_hash_user_id)
    end
   end

   it 'recieves the specified totem and the user holding time' do
    waiting_since_hash_user_id = "1393675200"
    expect(Stats).to receive(:capture_holding_time).with(totem, waiting_since_hash_user_id).and_call_original
    Stats.capture_holding_time(totem, waiting_since_hash_user_id)
   end
  end

  describe 'capture_waiting_time' do
   it 'sends totems:holding_time:#{totem} metric and the waiting time in minutes as a value to signalfx gauges' do
    Timecop.freeze("2014-03-01 13:00:00") do
     waiting_since_hash_next_user_id = "1393675200"
     expect(Stats).to receive(:send_gauges_to_signalFX).with("totems:waiting_time:#{totem}", 60)
     Stats.capture_waiting_time(totem, waiting_since_hash_next_user_id)
    end
   end

   it 'recieves the specified totem and the next user waiting time' do
     waiting_since_hash_next_user_id = "1393675200"
     expect(Stats).to receive(:capture_waiting_time).with(totem, waiting_since_hash_next_user_id).and_call_original
     Stats.capture_waiting_time(totem, waiting_since_hash_next_user_id)
   end
  end

  describe 'signalfx_dashboard' do
   it 'returns signalfx dashboard link' do
    expect(Stats).to receive(:signalfx_dashboard).and_return("https://app.signalfx.com/#/dashboard/FNSkEUVAYAA")
    Stats.signalfx_dashboard()
   end
  end

end