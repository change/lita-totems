require 'signalfx'

class Stats

  @@signalfx_client ||= SignalFx.new ENV['LITA_SIGNALFX_TOKEN']
  SIGNALFX_TOTEMS_METRICS_DASHBOARD = "https://app.signalfx.com/#/dashboard/FNSkEUVAYAA"

  def self.send_to_signalFX(metric, value)
    @@signalfx_client.send( 
      gauges:
        [ 
          {  
          :metric => metric,
          :value => value,
          :timestamp => (Time.now.to_f * 1000).to_i
        }
      ]
    )
  end

  # captures how many times a totem has being added
  def self.capture_totem_use(totem)
    self.send_to_signalFX("totems:add:#{totem}", 1)
  end

  # captures how many people are waiting for a totem.
  def self.capture_people_waiting(totem)
    self.send_to_signalFX("totems:people_waiting:#{totem}", 1)
  end

  # captures totem's holding time by user
  def self.capture_holding_time(totem, waiting_since_hash_user_id)
    user_holding_time_in_seconds = Time.now.to_i - waiting_since_hash_user_id.to_i
    user_holding_time_in_minutes = user_holding_time_in_seconds / 60
    self.send_to_signalFX("totems:holding_time:#{totem}",user_holding_time_in_minutes)
  end

  # captures totem's waiting time by the next user
  def self.capture_waiting_time(totem, waiting_since_hash_next_user_id)
    user_holding_time_in_seconds = Time.now.to_i - waiting_since_hash_next_user_id.to_i
    user_holding_time_in_minutes = user_holding_time_in_seconds / 60
    self.send_to_signalFX("totems:holding_time:#{totem}",user_holding_time_in_minutes)
  end

  def self.signalfx_dashboard
    SIGNALFX_TOTEMS_METRICS_DASHBOARD
  end

end